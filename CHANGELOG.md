## 2.0.3

-   Fixed `NDEFRecord.languageCode` being ignored when writing

## 2.0.2

-   Fixed a crash when reading tags containing records with a custom url protocol and well known type URL

## 2.0.1

-   Fixed writing TNF text records on iOS (credit to GitHub user @janipiippow)

## 2.0.0

-   Added `noSounds` flag to `NFCNormalReaderMode`

On Android, this tells the system not to play sounds when a NFC chip is scanned.

-   Support for writing NDEF messages has been added

Get acccess to tags using the new `.tag` property on messages, which you can
use to connect and write to tags.

-   Added the following methods for constructing NDEF messages:

`NDEFRecord.empty` for empty records

`NDEFRecord.plain` for `text/plain` records

`NDEFRecord.type` for records with custom types

`NDEFRecord.text` for records with well known text types

`NDEFRecord.uri` for records with well known URI types

`NDEFRecord.absoluteUri`

`NDEFRecord.external`

`NDEFRecord.custom`

-   **COULD BE BREAKING**: Records with type T and U (with well known TNF) will
    now be correctly constructed. URI records will have the URL prefix added to the
    `.payload` and Text records will now correctly have thr first prefix byte removed from the `.payload`. If you want the precise value, you can use the new `.data` property which excludes the URL prefix of URI records and language codes of Text records.

-   Added `.data` property to `NDEFRecord` which excludes URL prefixes and
    language codes from records with well known types.

-   Added `.languageCode` property to `NDEFRecord` which will contain the language
    code of a record with a well known text type.

-   Updated the `.tnf` property on `NDEFRecord`s. This is now an enumerable
    (`NFCTypeNameFormat`) with it's value mapped to the correct TNF value.
    This works on both Android and iOS where as it previously did not.

## 1.2.0

-   Added `id` property to `NDEFMessage` which contains the NFC tag's UID
-   Support for more card types on Android

## 1.1.1

-   Bugfix: Android sessions are now closed properly

## 1.1.0

-   Added support for reading from emulated host cards

## 1.0.0

-   First release, woohoo!
-   Support for reading NDEF formatted NFC tags on both Android and iOS
