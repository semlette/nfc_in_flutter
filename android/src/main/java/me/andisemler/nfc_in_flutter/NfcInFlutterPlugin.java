package me.andisemler.nfc_in_flutter;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.Intent;
import android.content.IntentFilter;
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
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

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
    private static final String LOG_TAG = "NfcInFlutterPlugin";

    private final Activity activity;
    private NfcAdapter adapter;
    private EventChannel.EventSink events;
    private String currentReadingMode = null;

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
                if (call.arguments instanceof HashMap) {
                    HashMap args = (HashMap) call.arguments;
                    String readerMode = (String) args.get("reader_mode");
                    if (readerMode != null) {
                        if (currentReadingMode != null && !readerMode.equals(currentReadingMode)) {
                            // Throw error if the user tries to start reading with another reading mode
                            // than the one currently active
                            result.error("NFCMultipleReadingModes", "multiple reading modes", "");
                            return;
                        }
                        switch (readerMode) {
                            case "normal":
                                startReading();
                                break;
                            case "foreground_dispatch":
                                startReadingWithForegroundDispatch();
                                break;
                            default:
                                result.error("NFCUnknownReaderMode", "unknown reader mode: " + readerMode, "");
                        }
                        return;
                    }
                }
                startReading();
                result.success(null);
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

    private void startReading() {
        adapter = NfcAdapter.getDefaultAdapter(activity);
        if (adapter == null) return;
        Bundle bundle = new Bundle();
        adapter.enableReaderMode(activity, this, NfcAdapter.FLAG_READER_NFC_A, bundle);
    }

    private void startReadingWithForegroundDispatch() {
        adapter = NfcAdapter.getDefaultAdapter(activity);
        if (adapter == null) return;
        Intent intent = new Intent(activity.getApplicationContext(), activity.getClass());
        intent.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);

        PendingIntent pendingIntent = PendingIntent.getActivity(activity.getApplicationContext(), 0, intent, 0);

        IntentFilter[] filters = new IntentFilter[1];
        String[][] techList = new String[][]{};

        filters[0] = new IntentFilter();
        filters[0].addAction(NfcAdapter.ACTION_NDEF_DISCOVERED);
        filters[0].addCategory(Intent.CATEGORY_DEFAULT);
        try {
            filters[0].addDataType("text/plain");
        } catch (IntentFilter.MalformedMimeTypeException e) {
            // TODO: THROW THE ERROR
            return;
        }

        adapter.enableForegroundDispatch(activity, pendingIntent, filters, techList);
    }

    @Override
    public void onListen(Object args, EventChannel.EventSink eventSink) {
        events = eventSink;
    }

    @Override
    public void onCancel(Object args) {
        events = null;
        currentReadingMode = null;
    }

    @Override
    public void onTagDiscovered(Tag tag) {
        Log.i(LOG_TAG, "new tag");
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

    private Map<String, Object> formatNDEFMessageToResult(Ndef ndef, NdefMessage message) {
        final Map<String, Object> result = new HashMap<>();
        List<Map<String, String>> records = new ArrayList<>();
        for (NdefRecord record : message.getRecords()) {
            Map<String, String> recordMap = new HashMap<>();
            recordMap.put("payload", new String(record.getPayload(), StandardCharsets.UTF_8));
            recordMap.put("id", new String(record.getId(), StandardCharsets.UTF_8));
            recordMap.put("type", new String(record.getType(), StandardCharsets.UTF_8));
            recordMap.put("tnf", String.valueOf(record.getTnf()));
            records.add(recordMap);
        }
        result.put("message_type", "ndef");
        result.put("type", ndef.getType());
        result.put("records", records);
        return result;
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

    @Override
    public boolean onNewIntent(Intent intent) {
        String action = intent.getAction();
        if (NfcAdapter.ACTION_NDEF_DISCOVERED.equals(action)) {

            String type = intent.getType();
            if (Objects.equals(type, "text/plain")) {

                Tag tag = intent.getParcelableExtra(NfcAdapter.EXTRA_TAG);
                handleNDEFTagFromIntent(tag);
                return true;
            } else {
                Log.d(LOG_TAG, "Wrong mime type: " + type);
            }
        } else if (NfcAdapter.ACTION_TECH_DISCOVERED.equals(action)) {

            // In case we would still use the Tech Discovered Intent
            Tag tag = intent.getParcelableExtra(NfcAdapter.EXTRA_TAG);
            String[] techList = tag.getTechList();
            String searchedTech = Ndef.class.getName();

            for (String tech : techList) {
                if (searchedTech.equals(tech)) {
                    handleNDEFTagFromIntent(tag);
                    return true;
                }
            }
        }
        return false;
    }

    private void handleNDEFTagFromIntent(Tag tag) {
        Ndef ndef = Ndef.get(tag);
        if (ndef == null) {
            return;
        }

        NdefMessage message = ndef.getCachedNdefMessage();
        eventSuccess(formatNDEFMessageToResult(ndef, message));
    }
}
