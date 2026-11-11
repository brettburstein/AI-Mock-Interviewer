// Tests for the citation check in index.html.
// Run with: node tests/citationCheck.test.js
//
// The check lives inside index.html between the "CITATION CHECK START" and
// "CITATION CHECK END" markers. This file pulls that exact block out and runs it,
// so the code being tested is the code that ships.

var fileSystem = require("fs");
var path = require("path");
var assert = require("assert");

var pagePath = path.join(__dirname, "..", "index.html");
var pageText = fileSystem.readFileSync(pagePath, "utf8");
var startMarker = "// CITATION CHECK START";
var endMarker = "// CITATION CHECK END";
var startIndex = pageText.indexOf(startMarker);
var endIndex = pageText.indexOf(endMarker);
if (startIndex === -1 || endIndex === -1) {
  throw new Error("Could not find the citation check markers in index.html");
}
var checkCode = pageText.slice(startIndex, endIndex);
var loadCheck = new Function(checkCode + "\nreturn { checkCitation: checkCitation, checkAllCitations: checkAllCitations, listFailedChecks: listFailedChecks };");
var citationCheck = loadCheck();

var rubricDimensions = [
  { key: "understanding" },
  { key: "approach" },
  { key: "correctness" },
  { key: "complexity" },
  { key: "code" }
];

var passedCount = 0;
function runTest(name, testFunction) {
  testFunction();
  passedCount = passedCount + 1;
  console.log("ok - " + name);
}

// Case 1: a correct two-sum explanation.
var correctTwoSumRecords = [
  { speaker: "interviewer", id: "", text: "Hi! Let's do Two Sum. What are your first thoughts?" },
  { speaker: "candidate", id: "T1", text: "So um the brute force is two loops, which is O of n squared." },
  { speaker: "interviewer", id: "", text: "Can you do better?" },
  { speaker: "candidate", id: "T2", text: "Yeah I'd use a hash map from value to index. For each number I check if target minus the number is already in the map, and that lookup is O(1) on average, so overall it's O(n) time and O(n) space." }
];

runTest("correct two-sum: a real quote from a real turn is verified", function () {
  var result = citationCheck.checkCitation(correctTwoSumRecords, {
    status: "scored", score: 5, evidenceId: "T2", excerpt: "so overall it's O(n) time and O(n) space"
  });
  assert.strictEqual(result.verified, true);
});

runTest("correct two-sum: case, curly quotes and extra spaces don't break a real quote", function () {
  var result = citationCheck.checkCitation(correctTwoSumRecords, {
    status: "scored", score: 5, evidenceId: "T2", excerpt: "“I'd use a  HASH MAP from value to index.”"
  });
  assert.strictEqual(result.verified, true);
});

runTest("correct two-sum: a paraphrase is rejected", function () {
  var result = citationCheck.checkCitation(correctTwoSumRecords, {
    status: "scored", score: 5, evidenceId: "T2", excerpt: "linear time with a dictionary"
  });
  assert.strictEqual(result.verified, false);
});

runTest("correct two-sum: a real quote cited from the wrong turn is rejected", function () {
  var result = citationCheck.checkCitation(correctTwoSumRecords, {
    status: "scored", score: 5, evidenceId: "T1", excerpt: "O(n) time and O(n) space"
  });
  assert.strictEqual(result.verified, false);
});

runTest("correct two-sum: interviewer lines can't be cited", function () {
  var result = citationCheck.checkCitation(correctTwoSumRecords, {
    status: "scored", score: 4, evidenceId: "", excerpt: "Can you do better?"
  });
  assert.strictEqual(result.verified, false);
});

// Case 2: a duplicate-input bug. The code stores the index before checking for the
// complement, so nums = [3, 3], target = 6 would return [0, 0].
var duplicateBugRecords = [
  { speaker: "candidate", id: "T1", text: "I'll store each number in a dictionary and look for the complement." },
  { speaker: "code", id: "C1", text: "def two_sum(nums, target):\n    seen = {}\n    for i, num in enumerate(nums):\n        seen[num] = i\n        if target - num in seen:\n            return [seen[target - num], i]" }
];

runTest("duplicate bug: quoting the buggy line from the code snapshot is verified", function () {
  var result = citationCheck.checkCitation(duplicateBugRecords, {
    status: "scored", score: 2, evidenceId: "C1", excerpt: "seen[num] = i"
  });
  assert.strictEqual(result.verified, true);
});

runTest("duplicate bug: an excerpt that spans two code lines still matches", function () {
  var result = citationCheck.checkCitation(duplicateBugRecords, {
    status: "scored", score: 2, evidenceId: "C1", excerpt: "seen[num] = i if target - num in seen"
  });
  assert.strictEqual(result.verified, true);
});

runTest("duplicate bug: a made-up claim about the code is rejected", function () {
  var result = citationCheck.checkCitation(duplicateBugRecords, {
    status: "scored", score: 5, evidenceId: "C1", excerpt: "checks the complement before inserting"
  });
  assert.strictEqual(result.verified, false);
});

runTest("duplicate bug: citing a code snapshot that doesn't exist is rejected", function () {
  var result = citationCheck.checkCitation(duplicateBugRecords, {
    status: "scored", score: 3, evidenceId: "C2", excerpt: "seen[num] = i"
  });
  assert.strictEqual(result.verified, false);
});

// Case 3: silence. The candidate never said or wrote anything.
var silentRecords = [
  { speaker: "interviewer", id: "", text: "Hi! Let's do Two Sum. What are your first thoughts?" }
];

runTest("silence: not_demonstrated passes the check", function () {
  var result = citationCheck.checkCitation(silentRecords, {
    status: "not_demonstrated", score: 0, evidenceId: "", excerpt: ""
  });
  assert.strictEqual(result.verified, true);
});

runTest("silence: a score that cites a turn that never happened is rejected", function () {
  var result = citationCheck.checkCitation(silentRecords, {
    status: "scored", score: 3, evidenceId: "T1", excerpt: "it's O(n)"
  });
  assert.strictEqual(result.verified, false);
});

runTest("silence: a full grade with every area scored lists five failures", function () {
  var dimensions = {};
  for (var index = 0; index < rubricDimensions.length; index++) {
    dimensions[rubricDimensions[index].key] = { status: "scored", score: 3, evidenceId: "T1", excerpt: "something" };
  }
  var checks = citationCheck.checkAllCitations(silentRecords, { dimensions: dimensions }, rubricDimensions);
  var failures = citationCheck.listFailedChecks(checks, rubricDimensions);
  assert.strictEqual(failures.length, 5);
});

runTest("bad grader output: a missing area is rejected instead of crashing", function () {
  var checks = citationCheck.checkAllCitations(correctTwoSumRecords, { dimensions: {} }, rubricDimensions);
  assert.strictEqual(checks.complexity.verified, false);
});

runTest("bad grader output: an empty excerpt is rejected", function () {
  var result = citationCheck.checkCitation(correctTwoSumRecords, {
    status: "scored", score: 4, evidenceId: "T2", excerpt: "  \"\" "
  });
  assert.strictEqual(result.verified, false);
});

console.log("\n" + passedCount + " tests passed");
