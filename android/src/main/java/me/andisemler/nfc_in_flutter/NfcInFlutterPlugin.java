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
import android.nfc.tech.NdefFormatable;
import android.os.Bundle;
import android.os.Handler;
import android.util.Log;

import java.io.IOException;
import java.math.BigInteger;
import java.nio.ByteBuffer;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

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
    }

    @Override
    public void onTagDiscovered(Tag tag) {
        lastTag = tag;
        Ndef ndef = Ndef.get(tag);
        if (ndef == null) {
            // tag is not in NDEF format; skip!
            return;
        }
        boolean closed = false;
        try {
            ndef.connect();
            NdefMessage message = ndef.getNdefMessage();
            if (message == null) {
                return;
            }
            try {
                ndef.close();
                closed = true;
            } catch (IOException e) {
                Log.e(LOG_TAG, "close NDEF tag error: " + e.getMessage());
            }
            eventSuccess(formatNDEFMessageToResult(ndef, message));
        } catch (IOException e) {
            Map<String, Object> details = new HashMap<>();
            details.put("fatal", true);
            eventError("IOError", e.getMessage(), details);
        } catch (FormatException e) {
            eventError("NDEFBadFormatError", e.getMessage(), null);
        } finally {
            // Close if the tag connection if it isn't already
            if (!closed) {
                try {
                    ndef.close();
                } catch (IOException e) {
                    Log.e(LOG_TAG, "close NDEF tag error: " + e.getMessage());
                }
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
            ndef.close();
        } catch (IOException e) {
            Log.e(LOG_TAG, "close NDEF tag error: " + e.getMessage());
        }
        Map result = formatNDEFMessageToResult(ndef, message);
        eventSuccess(result);
    }

    private Map<String, Object> formatNDEFMessageToResult(Ndef ndef, NdefMessage message) {
        final Map<String, Object> result = new HashMap<>();
        List<Map<String, String>> records = new ArrayList<>();
        for (NdefRecord record : message.getRecords()) {
            Map<String, String> recordMap = new HashMap<>();
            byte[] recordPayload = record.getPayload();
            Charset charset = StandardCharsets.UTF_8;
            short tnf = record.getTnf();
            byte[] type = record.getType();
            if (tnf == NdefRecord.TNF_WELL_KNOWN && Arrays.equals(type, NdefRecord.RTD_TEXT)) {
                charset = ((recordPayload[0] & 128) == 0) ? StandardCharsets.UTF_8 : StandardCharsets.UTF_16;
            }

            // If the record's tnf is well known and the RTD is set to URI,
            // the URL prefix should be added to the payload
            if (tnf == NdefRecord.TNF_WELL_KNOWN && Arrays.equals(type, NdefRecord.RTD_URI)) {
                recordMap.put("data", new String(recordPayload, 1, recordPayload.length - 1, charset));

                String url = "";
                byte prefixByte = recordPayload[0];
                // https://android.googlesource.com/platform/frameworks/base/+/master/core/java/android/nfc/NdefRecord.java#238
                switch (prefixByte) {
                    case 0x01:
                        url = "http://www.";
                        break;
                    case 0x02:
                        url = "https://www.";
                        break;
                    case 0x03:
                        url = "http://";
                        break;
                    case 0x04:
                        url = "https://";
                        break;
                    case 0x05:
                        url = "tel:";
                        break;
                    case 0x06:
                        url = "mailto:";
                        break;
                    case 0x07:
                        url = "ftp://anonymous:anonymous@";
                        break;
                    case 0x08:
                        url = "ftp://ftp.";
                        break;
                    case 0x09:
                        url = "ftps://";
                        break;
                    case 0x0A:
                        url = "sftp://";
                        break;
                    case 0x0B:
                        url = "smb://";
                        break;
                    case 0x0C:
                        url = "nfs://";
                        break;
                    case 0x0D:
                        url = "ftp://";
                        break;
                    case 0x0E:
                        url = "dav://";
                        break;
                    case 0x0F:
                        url = "news:";
                        break;
                    case 0x10:
                        url = "telnet://";
                        break;
                    case 0x11:
                        url = "imap:";
                        break;
                    case 0x12:
                        url = "rtsp://";
                        break;
                    case 0x13:
                        url = "urn:";
                        break;
                    case 0x14:
                        url = "pop:";
                        break;
                    case 0x15:
                        url = "sip:";
                        break;
                    case 0x16:
                        url = "sips";
                        break;
                    case 0x17:
                        url = "tftp:";
                        break;
                    case 0x18:
                        url = "btspp://";
                        break;
                    case 0x19:
                        url = "btl2cap://";
                        break;
                    case 0x1A:
                        url = "btgoep://";
                        break;
                    case 0x1B:
                        url = "btgoep://";
                        break;
                    case 0x1C:
                        url = "irdaobex://";
                        break;
                    case 0x1D:
                        url = "file://";
                        break;
                    case 0x1E:
                        url = "urn:epc:id:";
                        break;
                    case 0x1F:
                        url = "urn:epc:tag:";
                        break;
                    case 0x20:
                        url = "urn:epc:pat:";
                        break;
                    case 0x21:
                        url = "urn:epc:raw:";
                        break;
                    case 0x22:
                        url = "urn:epc:";
                        break;
                    case 0x23:
                        url = "urn:nfc:";
                        break;
                }
                recordMap.put("payload", url + new String(recordPayload, 1, recordPayload.length - 1, charset));
            } else if (tnf == NdefRecord.TNF_WELL_KNOWN && Arrays.equals(type, NdefRecord.RTD_TEXT)) {
                int languageCodeLength = (recordPayload[0] & 0x3f) + 1;
                recordMap.put("payload", new String(recordPayload, 1, recordPayload.length - 1, charset));
                recordMap.put("languageCode", new String(recordPayload, 1, languageCodeLength - 1, charset));
                recordMap.put("data", new String(recordPayload, languageCodeLength, recordPayload.length - languageCodeLength, charset));
            } else {
                recordMap.put("payload", new String(recordPayload, charset));
                recordMap.put("data", new String(recordPayload, charset));
            }

            recordMap.put("id", new String(record.getId(), StandardCharsets.UTF_8));
            recordMap.put("type", new String(record.getType(), StandardCharsets.UTF_8));

            String tnfValue;
            switch (tnf) {
                case NdefRecord.TNF_EMPTY:
                    tnfValue = "empty";
                    break;
                case NdefRecord.TNF_WELL_KNOWN:
                    tnfValue = "well_known";
                    break;
                case NdefRecord.TNF_MIME_MEDIA:
                    tnfValue = "mime_media";
                    break;
                case NdefRecord.TNF_ABSOLUTE_URI:
                    tnfValue = "absolute_uri";
                    break;
                case NdefRecord.TNF_EXTERNAL_TYPE:
                    tnfValue = "external_type";
                    break;
                case NdefRecord.TNF_UNCHANGED:
                    tnfValue = "unchanged";
                    break;
                default:
                    tnfValue = "unknown";
            }

            recordMap.put("tnf", tnfValue);
            records.add(recordMap);
        }
        byte[] idByteArray = ndef.getTag().getId();
        // Fancy string formatting snippet is from
        // https://gist.github.com/luixal/5768921#gistcomment-1788815
        result.put("id", String.format("%0" + (idByteArray.length * 2) + "X", new BigInteger(1, idByteArray)));
        result.put("message_type", "ndef");
        result.put("type", ndef.getType());
        result.put("records", records);
        result.put("writable", ndef.isWritable());
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
        for (int i = 0; i < amountOfRecords; i++) {
            Object mapRecordObj = mapRecords.get(i);
            if (!(mapRecordObj instanceof Map)) {
                throw new IllegalArgumentException("record is not a map");
            }
            Map mapRecord = (Map) mapRecordObj;
            String id = (String) mapRecord.get("id");
            if (id == null) {
                id = "";
            }
            String type = (String) mapRecord.get("type");
            if (type == null) {
                type = "";
            }
            String languageCode = (String) mapRecord.get("languageCode");
            if (languageCode == null) {
                languageCode = Locale.getDefault().getLanguage();
            }
            String payload = (String) mapRecord.get("payload");
            if (payload == null) {
                payload = "";
            }
            String tnf = (String) mapRecord.get("tnf");
            if (tnf == null) {
                throw new IllegalArgumentException("record tnf is null");
            }

            byte[] idBytes = id.getBytes();
            byte[] typeBytes = type.getBytes();
            byte[] languageCodeBytes = languageCode.getBytes(StandardCharsets.US_ASCII);
            byte[] payloadBytes = payload.getBytes();

            short tnfValue;
            // Construct record
            switch (tnf) {
                case "empty":
                    // Empty records are not allowed to have a ID, type or payload.
                    tnfValue = NdefRecord.TNF_EMPTY;
                    idBytes = null;
                    typeBytes = null;
                    payloadBytes = null;
                    break;
                case "well_known":
                    tnfValue = NdefRecord.TNF_WELL_KNOWN;
                    if (Arrays.equals(typeBytes, NdefRecord.RTD_TEXT)) {
                        // The following code basically constructs a text record like NdefRecord.createTextRecord() does,
                        // however NdefRecord.createTextRecord() is only available in SDK 21+ while nfc_in_flutter
                        // goes down to SDK 19.
                        ByteBuffer buffer = ByteBuffer.allocate(1 + languageCodeBytes.length + payloadBytes.length);
                        byte status = (byte) (languageCodeBytes.length & 0xFF);
                        buffer.put(status);
                        buffer.put(languageCodeBytes);
                        buffer.put(payloadBytes);
                        payloadBytes = buffer.array();
                    } else if (Arrays.equals(typeBytes, NdefRecord.RTD_URI)) {
                        // Instead of manually constructing a URI payload with the correct prefix and
                        // everything, create a record using NdefRecord.createUri and copy it's payload.
                        NdefRecord uriRecord = NdefRecord.createUri(payload);
                        payloadBytes = uriRecord.getPayload();
                    }
                    break;
                case "mime_media":
                    tnfValue = NdefRecord.TNF_MIME_MEDIA;
                    break;
                case "absolute_uri":
                    tnfValue = NdefRecord.TNF_ABSOLUTE_URI;
                    break;
                case "external_type":
                    tnfValue = NdefRecord.TNF_EXTERNAL_TYPE;
                    break;
                case "unchanged":
                    throw new IllegalArgumentException("records are not allowed to have their TNF set to UNCHANGED");
                default:
                    tnfValue = NdefRecord.TNF_UNKNOWN;
                    typeBytes = null;
            }
            records[i] = new NdefRecord(tnfValue, typeBytes, idBytes, payloadBytes);
        }
        return new NdefMessage(records);
    }

    private void writeNDEF(NdefMessage message) throws NfcInFlutterException {
        Ndef ndef = Ndef.get(lastTag);
        NdefFormatable formatable = NdefFormatable.get(lastTag);

        // Absolute try-catch monstrosity

        if (ndef != null) {
            try {
                ndef.connect();
                if (ndef.getMaxSize() < message.getByteArrayLength()) {
                    HashMap<String, Object> details = new HashMap<>();
                    details.put("maxSize", ndef.getMaxSize());
                    throw new NfcInFlutterException("NFCTagSizeTooSmallError", "message is too large for this tag", details);
                }
                try {
                    ndef.writeNdefMessage(message);
                } catch (IOException e) {
                    throw new NfcInFlutterException("IOError", "write to tag error: " + e.getMessage(), null);
                } catch (FormatException e) {
                    throw new NfcInFlutterException("NDEFBadFormatError", e.getMessage(), null);
                }
            } catch (IOException e) {
                throw new NfcInFlutterException("IOError", e.getMessage(), null);
            } finally {
                try {
                    ndef.close();
                } catch (IOException e) {
                    Log.e(LOG_TAG, "close NDEF tag error: " + e.getMessage());
                }
            }
        } else if (formatable != null) {
            boolean closed = false;
            try {
                formatable.connect();
                formatable.format(message);
                try {
                    formatable.close();
                    closed = true;
                } catch (IOException e) {
                    Log.e(LOG_TAG, "close NDEF formatable error: " + e.getMessage());
                }
            } catch (IOException e) {
                throw new NfcInFlutterException("IOError", e.getMessage(), null);
            } catch (FormatException e) {
                throw new NfcInFlutterException("NDEFBadFormatError", e.getMessage(), null);
            } finally {
                if (!closed) {
                    try {
                        formatable.close();
                    } catch (IOException e) {
                        Log.e(LOG_TAG, "close NDEF formatable error: " + e.getMessage());
                    }
                }
            }
        } else {
            throw new NfcInFlutterException("NDEFUnsupported", "tag doesn't support NDEF", null);
        }
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
