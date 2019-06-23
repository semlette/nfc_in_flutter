package me.andisemler.nfc_in_flutter;

import android.app.Activity;
import android.nfc.FormatException;
import android.nfc.NdefMessage;
import android.nfc.NdefRecord;
import android.nfc.NfcAdapter;
import android.nfc.Tag;
import android.nfc.tech.Ndef;
import android.os.Bundle;
import android.os.Handler;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;

/**
 * NfcInFlutterPlugin
 */
public class NfcInFlutterPlugin implements MethodCallHandler, EventChannel.StreamHandler, NfcAdapter.ReaderCallback {
    private static final String LOG_TAG = "NfcInFlutterPlugin";

    private final Activity activity;
    private NfcAdapter adapter;
    private EventChannel.EventSink events;

    /**
     * Plugin registration.
     */
    public static void registerWith(Registrar registrar) {
        final MethodChannel channel = new MethodChannel(registrar.messenger(), "nfc_in_flutter");
        final EventChannel tagChannel = new EventChannel(registrar.messenger(), "nfc_in_flutter/tags");
        NfcInFlutterPlugin plugin = new NfcInFlutterPlugin(registrar.activity());
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

    @Override
    public void onListen(Object args, EventChannel.EventSink eventSink) {
        events = eventSink;
    }

    @Override
    public void onCancel(Object args) {
        events = null;
    }

    @Override
    public void onTagDiscovered(Tag tag) {
        Ndef ndef = Ndef.get(tag);
        if (ndef == null) {
            // tag is not in NDEF format; skip!
            return;
        }
        try {
            final Map<String, Object> result = new HashMap<>();
            List<Map<String, String>> records = new ArrayList<>();
            ndef.connect();
            NdefMessage message = ndef.getNdefMessage();
            if (message == null) {
                return;
            }
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
            eventSuccess(result);
            try {
                ndef.close();
            } catch (IOException e) {
                Map<String, Object> details = new HashMap<>();
                details.put("fatal", false);
                eventError("IOError", e.getMessage(), details);
            }
        } catch (IOException e) {
            Map<String, Object> details = new HashMap<>();
            details.put("fatal", true);
            eventError("IOError", e.getMessage(), details);
        } catch (FormatException e) {
            eventError("NDEFBadFormatError", e.getMessage(), null);
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
