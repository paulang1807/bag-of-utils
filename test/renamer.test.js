import { test } from "node:test";
import assert from "node:assert";
import { getFileParts, generatePreview } from "../src/web/renamer.js";

test("getFileParts - splits names and extensions correctly", () => {
  // Standard file with single extension
  assert.deepEqual(getFileParts("test.txt", false), { name: "test", ext: ".txt" });
  
  // File with multiple dots
  assert.deepEqual(getFileParts("archive.tar.gz", false), { name: "archive.tar", ext: ".gz" });
  
  // File without extension
  assert.deepEqual(getFileParts("README", false), { name: "README", ext: "" });
  
  // Hidden file with no extension
  assert.deepEqual(getFileParts(".gitignore", false), { name: ".gitignore", ext: "" });
  
  // Hidden file with extension
  assert.deepEqual(getFileParts(".eslintrc.json", false), { name: ".eslintrc", ext: ".json" });
  
  // Directory with dot in name
  assert.deepEqual(getFileParts("docs.backup", true), { name: "docs.backup", ext: "" });
});

test("generatePreview - formats naming patterns correctly", () => {
  const files = [
    { name: "image-02.png", isDirectory: false, size: 1024 },
    { name: "image-01.png", isDirectory: false, size: 2048 },
    { name: "video.mp4", isDirectory: false, size: 5120 }
  ];

  // prefix_number format
  const res1 = generatePreview(files, {
    prefix: "vacation",
    format: "prefix_number",
    startIndex: 1,
    padding: 3
  });
  
  assert.strictEqual(res1.length, 3);
  // Files should be sorted naturally: image-01.png, image-02.png, video.mp4
  assert.strictEqual(res1[0].originalName, "image-01.png");
  assert.strictEqual(res1[0].newName, "vacation_001.png");
  assert.strictEqual(res1[1].originalName, "image-02.png");
  assert.strictEqual(res1[1].newName, "vacation_002.png");
  assert.strictEqual(res1[2].originalName, "video.mp4");
  assert.strictEqual(res1[2].newName, "vacation_003.mp4");

  // prefix_dash_number format
  const res2 = generatePreview(files, {
    prefix: "holiday",
    format: "prefix_dash_number",
    startIndex: 5,
    padding: 2
  });
  assert.strictEqual(res2[0].newName, "holiday-05.png");
  assert.strictEqual(res2[1].newName, "holiday-06.png");
  assert.strictEqual(res2[2].newName, "holiday-07.mp4");

  // prefix_space_number format
  const res3 = generatePreview(files, {
    prefix: "summer trip",
    format: "prefix_space_number",
    startIndex: 99,
    padding: 4
  });
  assert.strictEqual(res3[0].newName, "summer trip 0099.png");

  // prefix_original format
  const res4 = generatePreview(files, {
    prefix: "edited",
    format: "prefix_original"
  });
  assert.strictEqual(res4[0].newName, "edited_image-01.png");
  assert.strictEqual(res4[2].newName, "edited_video.mp4");
});

test("generatePreview - detects duplicate destination names", () => {
  // If we rename two different input files and they map to the same name
  // Note: generatePreview sorts them, but if we have duplicate name inputs (mocked)
  // or a format that maps everything to the same name, we should detect conflicts.
  // Wait, let's mock a duplicate name check by simulating a collision.
  // In our actual code, natural sorting works on unique filenames.
  // However, we can test conflict detection by passing mocked duplicate inputs to verify map logic.
  const files = [
    { name: "file1.txt", isDirectory: false, size: 100 },
    { name: "file1.txt", isDirectory: false, size: 150 } // duplicate input mock
  ];
  
  const res = generatePreview(files, {
    prefix: "backup",
    format: "prefix_original"
  });
  
  assert.strictEqual(res[0].newName, "backup_file1.txt");
  assert.strictEqual(res[1].newName, "backup_file1.txt");
  assert.strictEqual(res[0].conflict, true);
  assert.strictEqual(res[1].conflict, true);
  assert.match(res[0].conflictReason, /Duplicate destination name/);
});

test("generatePreview - throws on illegal macOS filename characters", () => {
  assert.throws(() => {
    generatePreview([], { prefix: "my/file" });
  }, /Prefix cannot contain illegal characters/);

  assert.throws(() => {
    generatePreview([], { prefix: "my:file" });
  }, /Prefix cannot contain illegal characters/);
});
