# AI Mock Interviewer — EECS 449 Group 7

A voice-driven mock coding interviewer for practicing data structures and algorithms. You pick a question, talk through your solution (using your device's dictation), optionally write code, ask for hints, and get graded at the end. Every score is tied to something you actually said or wrote.

Team: Anik, Brett, Dylan, Nick

## What's here

| File | What it is |
| --- | --- |
| `index.html` | The current MVP: the whole interviewer in one page. It uses Claude inside an artifact, or local Ollama when served with `server.py`. |
| `tests/citationCheck.test.js` | Tests for the web app's citation check. Run with `node tests/citationCheck.test.js`. |
| `jac/grader.jac` | The grader in Jac. byLLM fills in a typed `GradeReport`, and plain Jac code checks every citation. Runs on a local model through Ollama. |
| `jac/test_grader.jac` | Jac tests for the grader (no model needed). Run with `jac test test_grader.jac` from the `jac` folder. |
| `jac/transcripts/` | Sample interviews: a correct two-sum, the duplicate-input bug, and silence. |
| `jac/jac.toml` | byLLM settings: which Ollama model to use, temperature 0. |

## How grading works

1. **Every piece of evidence gets an ID.** Each thing the candidate says is a turn (`T1`, `T2`, …). Each time the code box changes and they send, that's a code snapshot (`C1`, `C2`, …). Interviewer lines are context only and can't be cited.
2. **The grader returns a typed result for each of five areas:** understanding the problem, explaining the approach, correctness, time and space complexity, and code. Each area has a `status` (`scored` or `not_demonstrated`), a 1–5 score, the ID of the supporting record, a word-for-word excerpt, a comment, and one thing to practice next.
3. **Citations are checked in code before any score is shown.** The cited ID has to exist and be a candidate turn or code snapshot, and the excerpt has to appear in that record (ignoring case, curly quotes, and whitespace). If any check fails, the grader gets one retry with the exact failures. If it still fails, that area's score is hidden and marked as not verified.
4. **Silence isn't scored as weak, it's "not demonstrated."** If the candidate says nothing at all, the page grades locally without calling the model.
5. **Read, not run.** The grader is told it never executed the code, and code evidence is labeled "read, not run" in the report.

The report includes the full interview record with IDs, and each evidence quote links to its record.

## Running the web app with local Ollama

With Ollama running and Llama 3.1 8B installed:

```
ollama pull llama3.1:8b
python3 server.py
```

Then open `http://127.0.0.1:8000`. The server also recognizes installed variants whose names begin with `llama3.1:8b-`. Set `OLLAMA_MODEL` to use a different model.

## Running the Jac grader

One-time setup:

```
pip install jaclang byllm
ollama pull llama3.1:8b        # or whatever model you set in jac/jac.toml
```

Then, from the `jac` folder, with Ollama running:

```
jac run grader.jac transcripts/two_sum_correct.json
```

To grade a real interview from the web app, finish it, click **Copy transcript for Jac grader**, paste into a new `.json` file in `jac/transcripts/`, and run the grader on that file.

How it works:

- `grade_interview(...) -> GradeReport by llm()` gets a typed result back: five `DimensionGrade`s, each with `status` (`SCORED` or `NOT_DEMONSTRATED`), `score`, `evidence_id`, `excerpt`, `comment`, and `practice_suggestion`. byLLM retries on its own if the output doesn't fit the types.
- `check_citation` is plain Jac: the ID has to be a real candidate record, and the excerpt has to be in it. If anything fails, `regrade_interview` gets one retry with the exact failures. Anything still failing is printed as NOT SHOWN.
- An interview where the candidate said nothing never calls the model.
- The rubric and rules live in the `sem grade_interview` string, because that's what reaches the model. (We checked: `sem` notes on nested object fields and enum fields don't make it into what byLLM sends.)

Built and tested with jaclang 0.16.7 and byllm 0.6.19. Not yet run against a real Ollama model.

## Tests

Both test suites cover the three cases from our TA's guide. `node tests/citationCheck.test.js` (web app) and `jac test test_grader.jac` (Jac grader, 15 tests, uses byLLM's mock model instead of a real one):

- a correct two-sum explanation (real quotes pass; paraphrases, wrong-turn citations, and interviewer lines fail)
- a duplicate-input bug (`seen[num] = i` before the complement check; a real quote of the bug passes, a made-up claim fails)
- silence (`not_demonstrated` passes; any score citing a turn that never happened fails)

The test pulls the check straight out of `index.html` (between the `CITATION CHECK START` / `END` markers), so it tests the code that ships.

The local server's model-tag resolution tests run with `python3 -m unittest tests/test_server.py`.

## Still to do

- Pick the Ollama model, pull it on the demo computer ahead of time, and do a full dry run of interview plus Jac grading before presenting.
- Connect the web app to the Jac grader directly (right now you copy the transcript over).
- Optionally move the interviewer itself to Jac; the web app can now call Ollama through `server.py`.
- System design questions (DSA only for now).
