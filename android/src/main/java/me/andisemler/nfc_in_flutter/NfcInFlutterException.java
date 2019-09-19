package me.andisemler.nfc_in_flutter;

class NfcInFlutterException extends Exception {
    String code;
    String message;
    Object details;

    NfcInFlutterException(String code, String message, Object details) {
        this.code = code;
        this.message = message;
        this.details = details;
    }
}
