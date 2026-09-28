import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow_pdf/models/university_file.dart';
import 'package:studyflow_pdf/services/university_service.dart';

/// Fixtures, so the tests read as behaviour rather than as data.
UniversityFile libraryFile({
  required String name,
  required String fileHash,
  required String storagePath,
}) {
  return UniversityFile(
    id: 'id-$fileHash',
    universityId: 'uni-1',
    folderId: 'folder-1',
    name: name,
    fileHash: fileHash,
    storagePath: storagePath,
    sizeBytes: 1024,
    uploadedBy: 'lecturer-1',
    uploadedAt: DateTime(2026, 9, 28),
  );
}

/// Locks the rule that decides which library rows read as "already downloaded".
///
/// A PDF sitting in `university_pdfs` opens instantly and offline; one that is
/// missing it has to wait on the network. Both listings — the sidebar's folder
/// tree and the full library panel — have to reach the same verdict about the
/// same file, which is why the matching lives in one place.
///
/// The failure this guards is the quiet one: a file that *is* on disk reported
/// as missing looks like a styling bug, but it re-downloads bytes that were
/// already there and, offline, it hides a file the user actually has.
void main() {
  test('a record whose storage key is prefixed still matches its basename', () {
    final files = [
      libraryFile(
        name: 'LCD1602.pdf',
        fileHash: 'hash-a',
        storagePath: 'uni-1/folder-a/1699283200-LCD1602.pdf',
      ),
    ];
    // The upload prefixes the key with a timestamp, so the disk name is not the
    // display name. The listing is asked about the key's basename because that
    // is the name the bytes were written under.
    final onDisk = {'1699283200-LCD1602.pdf'};

    expect(
      UniversityService.downloadedBasenameFor(files.single),
      '1699283200-LCD1602.pdf',
    );
    expect(UniversityService.downloadedHashesIn(onDisk, files), {'hash-a'});
  });

  test('a malformed storage key falls back to the display name', () {
    final files = [
      libraryFile(
        name: 'DSP-1-ok.pdf',
        fileHash: 'hash-b',
        storagePath: 'DSP-1-ok.pdf',
      ),
    ];
    final onDisk = {'DSP-1-ok.pdf'};

    expect(UniversityService.downloadedHashesIn(onDisk, files), {'hash-b'});
  });

  test('an empty storage path is the same file as its display name', () {
    // Records written before storage paths were populated exist in the wild, and
    // the basename rule has to name them something rather than throw.
    final file = libraryFile(
      name: 'LCD1602.pdf',
      fileHash: 'hash-c',
      storagePath: '',
    );

    expect(UniversityService.downloadedBasenameFor(file), 'LCD1602.pdf');
  });

  test('a file that is not on disk is never marked', () {
    final files = [
      libraryFile(
        name: 'LCD1602.pdf',
        fileHash: 'hash-a',
        storagePath: 'uni-1/folder-a/1699283200-LCD1602.pdf',
      ),
      libraryFile(
        name: 'DSP-1-ok.pdf',
        fileHash: 'hash-b',
        storagePath: 'uni-1/folder-a/DSP-1-ok.pdf',
      ),
    ];
    // Only the first was ever downloaded. A near-miss name must not match: the
    // hashes are what the UI keys on, and a false positive promises an offline
    // open that will fail.
    final onDisk = {'1699283200-LCD1602.pdf'};

    expect(UniversityService.downloadedHashesIn(onDisk, files), {'hash-a'});
  });

  test('an unreadable directory listing marks nothing', () {
    final files = [
      libraryFile(
        name: 'LCD1602.pdf',
        fileHash: 'hash-a',
        storagePath: 'uni-1/folder-a/1699283200-LCD1602.pdf',
      ),
    ];

    // getDownloadedFileNames() answers with an empty set when the directory
    // cannot be read, and an empty answer has to mean "nothing is marked"
    // rather than "everything is". That is the whole reason the fetch and this
    // matching are two calls: the caller keeps the right to interpret a failure
    // instead of having a partial listing look authoritative.
    expect(UniversityService.downloadedHashesIn(<String>{}, files), isEmpty);
  });
}
