# AI Mock Interviewer - EECS 449 Group 7

A voice-driven mock coding interviewer for practicing data structures and algorithms. You pick a question, talk through your solution (using your device's dictation), optionally write code, ask for hints, and get graded at the end. Every score is tied to something you actually said or wrote.

Team: Anik, Brett, Dylan, Nick

## What's here

| File | What it is |
| --- | --- |
| `index.html` | The current MVP: the whole interviewer in one page. It runs as a Claude artifact and calls the model through `window.claude`. |
| `tests/citationCheck.test.js` | Tests for the citation check. Run with `node tests/citationCheck.test.js`. |

## How grading works

1. **Every piece of evidence gets an ID.** Each thing the candidate says is a turn (`T1`, `T2`, …). Each time the code box changes and they send, that's a code snapshot (`C1`, `C2`, …). Interviewer lines are context only and can't be cited.
2. **The grader returns a typed result for each of five areas:** understanding the problem, explaining the approach, correctness, time and space complexity, and code. Each area has a `status` (`scored` or `not_demonstrated`), a 1–5 score, the ID of the supporting record, a word-for-word excerpt, a comment, and one thing to practice next.
3. **Citations are checked in code before any score is shown.** The cited ID has to exist and be a candidate turn or code snapshot, and the excerpt has to appear in that record (ignoring case, curly quotes, and whitespace). If any check fails, the grader gets one retry with the exact failures. If it still fails, that area's score is hidden and marked as not verified.
4. **Silence isn't scored as weak, it's "not demonstrated."** If the candidate says nothing at all, the page grades locally without calling the model.
5. **Read, not run.** The grader is told it never executed the code, and code evidence is labeled "read, not run" in the report.

The report includes the full interview record with IDs, and each evidence quote links to its record.

## Tests

`node tests/citationCheck.test.js` covers the three cases from our TA's guide:

- a correct two-sum explanation (real quotes pass; paraphrases, wrong-turn citations, and interviewer lines fail)
- a duplicate-input bug (`seen[num] = i` before the complement check; a real quote of the bug passes, a made-up claim fails)
- silence (`not_demonstrated` passes; any score citing a turn that never happened fails)

The test pulls the check straight out of `index.html` (between the `CITATION CHECK START` / `END` markers), so it tests the code that ships.

## Still to do

- Port the grading function to Jac with typed model outputs (Jac v0.39.2).
- Run the interview and grading against a local model through Ollama for the demo, with the model downloaded ahead of time, and do a full dry run on the demo computer before presenting.
- System design questions (DSA only for now).
