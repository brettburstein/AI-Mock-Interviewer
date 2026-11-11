"""Tests for grader.jac. Run with: jac test test_grader.jac

These never call a real model. The citation-check tests are plain code. The
end-to-end tests swap in byLLM's mock model ("mockllm"), which hands back the
GradeReport we give it, so we can check what the grader does with good and bad
citations without Ollama running.

Covers the three cases from the TA's guide: a correct two-sum explanation, a
duplicate-input bug, and silence.
"""

import grader;
import from byllm.lib { Model }

# ---------- Helpers ----------

def scored(evidence_id: str, excerpt: str, score: int) -> grader.DimensionGrade {
    return grader.DimensionGrade(
        status=grader.EvidenceStatus.SCORED,
        score=score,
        evidence_id=evidence_id,
        excerpt=excerpt,
        comment="test comment",
        practice_suggestion="test practice"
    );
}

def not_shown -> grader.DimensionGrade {
    return grader.not_demonstrated("nothing here");
}

def build_report(
    understanding: grader.DimensionGrade,
    approach: grader.DimensionGrade,
    correctness: grader.DimensionGrade,
    complexity: grader.DimensionGrade,
    code: grader.DimensionGrade
) -> grader.GradeReport {
    return grader.GradeReport(
        understanding=understanding,
        approach=approach,
        correctness=correctness,
        complexity=complexity,
        code=code,
        summary="test summary",
        strengths=[],
        improvements=[]
    );
}

"""Swaps the grader's model for byLLM's mock, which hands back these reports in order."""
def use_mock_model(reports: list) -> None {
    grader.llm = Model(model_name="mockllm", config={"outputs": reports});
}

glob correct_transcript = grader.load_transcript("transcripts/two_sum_correct.json");
glob duplicate_bug_transcript = grader.load_transcript("transcripts/two_sum_duplicate_bug.json");
glob silence_transcript = grader.load_transcript("transcripts/silence.json");

# ---------- Case 1: correct two-sum explanation ----------

test "correct two-sum: a real quote from a real turn is verified" {
    check = grader.check_citation(
        correct_transcript.candidate_records,
        scored("T2", "so overall it's O(n) time and O(n) space", 5)
    );
    assert check.verified;
}

test "correct two-sum: case, curly quotes and extra spaces don't break a real quote" {
    check = grader.check_citation(
        correct_transcript.candidate_records,
        scored("T2", "“I’d use a  HASH MAP from value to index.”", 5)
    );
    assert check.verified;
}

test "correct two-sum: a paraphrase is rejected" {
    check = grader.check_citation(
        correct_transcript.candidate_records,
        scored("T2", "linear time with a dictionary", 5)
    );
    assert not check.verified;
}

test "correct two-sum: a real quote cited from the wrong turn is rejected" {
    check = grader.check_citation(
        correct_transcript.candidate_records,
        scored("T1", "O(n) time and O(n) space", 5)
    );
    assert not check.verified;
}

test "correct two-sum: interviewer lines can't be cited" {
    check = grader.check_citation(
        correct_transcript.candidate_records,
        scored("I1", "Can you do better than that?", 4)
    );
    assert not check.verified;
}

test "correct two-sum: a fully cited grade goes straight through with no retry" {
    good_report = build_report(
        scored("T3", "check for the complement before I insert the current number", 5),
        scored("T2", "I'd use a hash map from value to index", 5),
        scored("C1", "if target - num in seen", 5),
        scored("T2", "so overall it's O(n) time and O(n) space", 5),
        scored("C1", "seen[num] = i", 4)
    );
    mock_outputs: list = [good_report];
    use_mock_model(mock_outputs);
    checked = grader.grade_with_citation_checks(
        correct_transcript.question,
        correct_transcript.candidate_records,
        correct_transcript.interviewer_lines,
        correct_transcript.hints_used
    );
    assert not checked.used_retry;
    assert len(grader.list_failed_checks(checked.checks)) == 0;
    assert len(mock_outputs) == 0;
}

# ---------- Case 2: duplicate-input bug ----------

test "duplicate bug: quoting the buggy line from the code snapshot is verified" {
    check = grader.check_citation(
        duplicate_bug_transcript.candidate_records,
        scored("C1", "seen[num] = i", 2)
    );
    assert check.verified;
}

test "duplicate bug: an excerpt that spans two code lines still matches" {
    check = grader.check_citation(
        duplicate_bug_transcript.candidate_records,
        scored("C1", "seen[num] = i if target - num in seen", 2)
    );
    assert check.verified;
}

test "duplicate bug: a made-up claim about the code is rejected" {
    check = grader.check_citation(
        duplicate_bug_transcript.candidate_records,
        scored("C1", "checks the complement before inserting", 5)
    );
    assert not check.verified;
}

test "duplicate bug: a made-up citation triggers one retry, and the fixed grade is kept" {
    made_up_report = build_report(
        not_shown(),
        scored("T1", "look for the complement", 3),
        scored("C1", "checks the complement before inserting", 5),
        not_shown(),
        scored("C1", "seen[num] = i", 2)
    );
    fixed_report = build_report(
        not_shown(),
        scored("T1", "look for the complement", 3),
        scored("C1", "seen[num] = i", 2),
        not_shown(),
        scored("C1", "seen[num] = i", 2)
    );
    use_mock_model([made_up_report, fixed_report]);
    checked = grader.grade_with_citation_checks(
        duplicate_bug_transcript.question,
        duplicate_bug_transcript.candidate_records,
        duplicate_bug_transcript.interviewer_lines,
        duplicate_bug_transcript.hints_used
    );
    assert checked.used_retry;
    assert checked.checks["correctness"].verified;
    assert checked.grade_report.correctness.score == 2;
}

test "duplicate bug: if the retry still makes things up, that score is hidden" {
    made_up_report = build_report(
        not_shown(),
        scored("T1", "look for the complement", 3),
        scored("C1", "checks the complement before inserting", 5),
        not_shown(),
        scored("C1", "seen[num] = i", 2)
    );
    use_mock_model([made_up_report, made_up_report]);
    checked = grader.grade_with_citation_checks(
        duplicate_bug_transcript.question,
        duplicate_bug_transcript.candidate_records,
        duplicate_bug_transcript.interviewer_lines,
        duplicate_bug_transcript.hints_used
    );
    assert checked.used_retry;
    assert not checked.checks["correctness"].verified;
    printed = grader.format_report(checked, duplicate_bug_transcript.candidate_records);
    assert "CORRECTNESS: NOT SHOWN" in printed;
    assert "TOTAL: 5 / 25" in printed;
}

test "duplicate bug: code evidence is labeled read, not run" {
    good_report = build_report(
        not_shown(),
        scored("T1", "look for the complement", 3),
        scored("C1", "seen[num] = i", 2),
        not_shown(),
        scored("C1", "seen[num] = i", 2)
    );
    use_mock_model([good_report]);
    checked = grader.grade_with_citation_checks(
        duplicate_bug_transcript.question,
        duplicate_bug_transcript.candidate_records,
        duplicate_bug_transcript.interviewer_lines,
        duplicate_bug_transcript.hints_used
    );
    printed = grader.format_report(checked, duplicate_bug_transcript.candidate_records);
    assert "your code, read not run" in printed;
}

# ---------- Case 3: silence ----------

test "silence: not_demonstrated passes the check" {
    check = grader.check_citation(silence_transcript.candidate_records, not_shown());
    assert check.verified;
}

test "silence: a score that cites a turn that never happened is rejected" {
    check = grader.check_citation(silence_transcript.candidate_records, scored("T1", "it's O(n)", 3));
    assert not check.verified;
}

test "silence: grading an empty interview never calls the model" {
    # The mock has no answers queued, so if the grader called it, this test would crash.
    mock_outputs: list = [];
    use_mock_model(mock_outputs);
    checked = grader.grade_with_citation_checks(
        silence_transcript.question,
        silence_transcript.candidate_records,
        silence_transcript.interviewer_lines,
        silence_transcript.hints_used
    );
    assert len(mock_outputs) == 0;
    assert checked.grade_report.complexity.status == grader.EvidenceStatus.NOT_DEMONSTRATED;
    printed = grader.format_report(checked, silence_transcript.candidate_records);
    assert "TOTAL: 0 / 25" in printed;
}
