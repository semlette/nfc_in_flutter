package me.andisemler.nfc_in_flutter;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.Intent;
import android.nfc.FormatException;
import android.nfc.NdefMessage;
import android.nfc.NdefRecord;
import android.nfc.NfcAdapter;
import android.nfc.Tag;
import android.nfc.tech.Ndef;
import android.os.Bundle;
import android.os.Handler;
import android.util.Log;

import java.io.IOException;
import java.math.BigInteger;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.text.Format;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.WeakHashMap;

import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry;
import io.flutter.plugin.common.PluginRegistry.Registrar;

/**
 * NfcInFlutterPlugin
 */
public class NfcInFlutterPlugin implements MethodCallHandler,
        EventChannel.StreamHandler,
        PluginRegistry.NewIntentListener,
        NfcAdapter.ReaderCallback {

    private static final String NORMAL_READER_MODE = "normal";
    private static final String DISPATCH_READER_MODE = "dispatch";
    private final int DEFAULT_READER_FLAGS = NfcAdapter.FLAG_READER_NFC_A | NfcAdapter.FLAG_READER_NFC_B | NfcAdapter.FLAG_READER_NFC_F | NfcAdapter.FLAG_READER_NFC_V;
    private static final String LOG_TAG = "NfcInFlutterPlugin";

    private final Activity activity;
    private NfcAdapter adapter;
    private EventChannel.EventSink events;

    private String currentReaderMode = null;
    private Tag lastTag = null;

    /**
     * Plugin registration.
     */
    public static void registerWith(Registrar registrar) {
        final MethodChannel channel = new MethodChannel(registrar.messenger(), "nfc_in_flutter");
        final EventChannel tagChannel = new EventChannel(registrar.messenger(), "nfc_in_flutter/tags");
        NfcInFlutterPlugin plugin = new NfcInFlutterPlugin(registrar.activity());
        registrar.addNewIntentListener(plugin);
        channel.setMethodCallHandler(plugin);
        tagChannel.setStreamHandler(plugin);
    }

    private NfcInFlutterPlugin(Activity activity) {
        this.activity = activity;
    }

    @Override
    public void onMethodCall(MethodCall call, Result result) {
        switch (call.method) {
            case "readNDEFSupported":
                result.success(nfcIsEnabled());
                break;
            case "startNDEFReading":
                if (!(call.arguments instanceof HashMap)) {
                    result.error("MissingArguments", "startNDEFReading was called with no arguments", "");
                    return;
                }
                HashMap args = (HashMap) call.arguments;
                String readerMode = (String) args.get("reader_mode");
                if (readerMode == null) {
                    result.error("MissingReaderMode", "startNDEFReading was called without a reader mode", "");
                    return;
                }

                if (currentReaderMode != null && !readerMode.equals(currentReaderMode)) {
                    // Throw error if the user tries to start reading with another reading mode
                    // than the one currently active
                    result.error("NFCMultipleReaderModes", "multiple reader modes", "");
                    return;
                }
                currentReaderMode = readerMode;
                switch (readerMode) {
                    case NORMAL_READER_MODE:
                        boolean noSounds = (boolean) args.get("no_platform_sounds");
                        startReading(noSounds);
                        break;
                    case DISPATCH_READER_MODE:
                        startReadingWithForegroundDispatch();
                        break;
                    default:
                        result.error("NFCUnknownReaderMode", "unknown reader mode: " + readerMode, "");
                        return;
                }
                result.success(null);
                break;
            case "writeNDEF":
                HashMap writeArgs = call.arguments();
                if (writeArgs == null) {
                    result.error("NFCMissingArguments", "missing arguments", null);
                    break;
                }
                try {
                    Map messageMap = (Map) writeArgs.get("message");
                    if (messageMap == null) {
                        result.error("NFCMissingNDEFMessage", "a ndef message was not given", null);
                        break;
                    }
                    NdefMessage message = formatMapToNDEFMessage(messageMap);
                    writeNDEF(message);
                    result.success(null);
                } catch (NfcInFlutterException e) {
                    result.error(e.code, e.message, e.details);
                } catch (IOException e) {
                    result.error("IOError", e.getMessage(), null);
                } catch (FormatException e) {
                    result.error("NDEFBadFormatError", e.getMessage(), null);
                }
                break;
            default:
                result.notImplemented();
        }
    }

    private Boolean nfcIsEnabled() {
        NfcAdapter adapter = NfcAdapter.getDefaultAdapter(activity);
        if (adapter == null) return false;
        return adapter.isEnabled();
    }

    private void startReading(boolean noSounds) {
        adapter = NfcAdapter.getDefaultAdapter(activity);
        if (adapter == null) return;
        Bundle bundle = new Bundle();
        int flags = DEFAULT_READER_FLAGS;
        if (noSounds) {
            flags = flags | NfcAdapter.FLAG_READER_NO_PLATFORM_SOUNDS;
        }
        adapter.enableReaderMode(activity, this, flags, bundle);
    }

    private void startReadingWithForegroundDispatch() {
        adapter = NfcAdapter.getDefaultAdapter(activity);
        if (adapter == null) return;
        Intent intent = new Intent(activity.getApplicationContext(), activity.getClass());
        intent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);

        PendingIntent pendingIntent = PendingIntent.getActivity(activity.getApplicationContext(), 0, intent, 0);
        String[][] techList = new String[][]{};

        adapter.enableForegroundDispatch(activity, pendingIntent, null, techList);
    }

    @Override
    public void onListen(Object args, EventChannel.EventSink eventSink) {
        events = eventSink;
    }

    @Override
    public void onCancel(Object args) {
        switch (currentReaderMode) {
            case NORMAL_READER_MODE:
                adapter.disableReaderMode(activity);
                break;
            case DISPATCH_READER_MODE:
                adapter.disableForegroundDispatch(activity);
                break;
            default:
                Log.e(LOG_TAG, "unknown reader mode: " + currentReaderMode);
        }
        events = null;
        currentReaderMode = null;
    }

    @Override
    public void onTagDiscovered(Tag tag) {
        lastTag = tag;
        Ndef ndef = Ndef.get(tag);
        if (ndef == null) {
            // tag is not in NDEF format; skip!
            return;
        }
        try {
            ndef.connect();
            NdefMessage message = ndef.getNdefMessage();
            if (message == null) {
                return;
            }
            eventSuccess(formatNDEFMessageToResult(ndef, message));
        } catch (IOException e) {
            Map<String, Object> details = new HashMap<>();
            details.put("fatal", true);
            eventError("IOError", e.getMessage(), details);
        } catch (FormatException e) {
            eventError("NDEFBadFormatError", e.getMessage(), null);
        } finally {
            try {
                ndef.close();
            } catch (IOException e) {
                Map<String, Object> details = new HashMap<>();
                details.put("fatal", false);
                eventError("IOError", e.getMessage(), details);
            }
        }
    }

    @Override
    public boolean onNewIntent(Intent intent) {
        String action = intent.getAction();
        if (NfcAdapter.ACTION_NDEF_DISCOVERED.equals(action)) {
            Tag tag = intent.getParcelableExtra(NfcAdapter.EXTRA_TAG);
            lastTag = tag;
            handleNDEFTagFromIntent(tag);
            return true;
        }
        return false;
    }

    private void handleNDEFTagFromIntent(Tag tag) {
        Ndef ndef = Ndef.get(tag);
        if (ndef == null) {
            return;
        }

        NdefMessage message = ndef.getCachedNdefMessage();
        try {
            Map result = formatNDEFMessageToResult(ndef, message);
            eventSuccess(result);
        } catch (FormatException e) {
            eventError("NDEFBadFormatError", e.getMessage(), null);
        }
    }

    private Map<String, Object> formatNDEFMessageToResult(Ndef ndef, NdefMessage message) throws FormatException {
        final Map<String, Object> result = new HashMap<>();
        List<Map<String, String>> records = new ArrayList<>();
        for (NdefRecord record : message.getRecords()) {
            Map<String, String> recordMap = new HashMap<>();
            byte[] recordPayload = record.getPayload();
            int spliceLength = 0;
            Charset charset = StandardCharsets.UTF_8;
            if (record.getTnf() == NdefRecord.TNF_WELL_KNOWN) {
                byte[] type = record.getType();
                if (Arrays.equals(type, NdefRecord.RTD_TEXT)) {
                    charset = ((recordPayload[0] & 128) == 0) ? StandardCharsets.UTF_8 : StandardCharsets.UTF_16;
                    spliceLength = (recordPayload[0] & 51) + 1; // Language code length
                } else if (Arrays.equals(type, NdefRecord.RTD_URI)) {
                    int prefixIndex = (recordPayload[0] & 0xff);
                    if (prefixIndex >= 44) {
                        throw new FormatException("Record payload has an invalid URI prefix");
                    }
                    spliceLength = 1;
                }
            }

            recordMap.put("payload", new String(recordPayload, charset));
            recordMap.put("data", new String(recordPayload, spliceLength, recordPayload.length - spliceLength, charset));
            recordMap.put("id", new String(record.getId(), StandardCharsets.UTF_8));
            recordMap.put("type", new String(record.getType(), StandardCharsets.UTF_8));
            recordMap.put("tnf", String.valueOf(record.getTnf()));
            records.add(recordMap);
        }
<<<<<<< HEAD
        byte[] idByteArray = ndef.getTag().getId();
        // Fancy string formatting snippet is from
        // https://gist.github.com/luixal/5768921#gistcomment-1788815
        result.put("id", String.format("%0" + (idByteArray.length * 2) + "X", new BigInteger(1, idByteArray)));
=======
        result.put("id", new String(ndef.getTag().getId(), StandardCharsets.UTF_8));
>>>>>>> writing
        result.put("message_type", "ndef");
        result.put("type", ndef.getType());
        result.put("records", records);
        result.put("writable", true);
        return result;
    }

    private NdefMessage formatMapToNDEFMessage(Map map) throws IllegalArgumentException {
        Object mapRecordsObj = map.get("records");
        if (mapRecordsObj == null) {
            throw new IllegalArgumentException("missing records");
        } else if (!(mapRecordsObj instanceof List)) {
            throw new IllegalArgumentException("map key 'records' is not a list");
        }
        List mapRecords = (List) mapRecordsObj;
        int amountOfRecords = mapRecords.size();
        NdefRecord[] records = new NdefRecord[amountOfRecords];
        for (int i = 0;i < amountOfRecords; i++) {
            Object mapRecordObj = mapRecords.get(i);
            if (!(mapRecordObj instanceof Map)) {
                throw new IllegalArgumentException("record is not a map");
            }
            Map mapRecord = (Map) mapRecordObj;
            records[i] = NdefRecord.createMime(
                (String) mapRecord.get("type"),
                ((String) mapRecord.get("payload")).getBytes()
            );
        }
        return new NdefMessage(records);
    }

    private void writeNDEF(NdefMessage message) throws NfcInFlutterException, IOException, FormatException {
        if (lastTag == null) {
            throw new NfcInFlutterException("NFCTagUnavailable", "tag is no longer available", null);
        }
        Ndef ndef = Ndef.get(lastTag);
        if (ndef == null) {
            throw new NfcInFlutterException("NDEFUnsupported", "tag doesn't support NDEF", null);
        }
        ndef.connect();
        ndef.writeNdefMessage(message);
    }

    private void eventSuccess(final Object result) {
        Handler mainThread = new Handler(activity.getMainLooper());
        Runnable runnable = new Runnable() {
            @Override
            public void run() {
                if (events != null) {
                    // Event stream must be handled on main/ui thread
                    events.success(result);
                }
            }
        };
        mainThread.post(runnable);
    }

    private void eventError(final String code, final String message, final Object details) {
        Handler mainThread = new Handler(activity.getMainLooper());
        Runnable runnable = new Runnable() {
            @Override
            public void run() {
                if (events != null) {
                    // Event stream must be handled on main/ui thread
                    events.error(code, message, details);
                }
            }
        };
        mainThread.post(runnable);
    }
}
