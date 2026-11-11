"""Group 7 AI Mock Interviewer: the grader, written in Jac.

The model fills in a typed GradeReport through byLLM. Plain Jac code then checks
every citation before a score is allowed through:
  1. the cited ID has to be a real candidate turn (T1, T2...) or code snapshot (C1, C2...)
  2. the quoted excerpt has to actually appear in that record

If any citation fails, the model gets one retry with the exact failures. If it still
fails, that area is marked unverified and its score is hidden.

Run it:  jac run grader.jac transcripts/two_sum_correct.json
Test it: jac test test_grader.jac
"""

import json;
import sys;

# ---------- Types the model has to fill in ----------

enum EvidenceStatus {
    SCORED = "scored",
    NOT_DEMONSTRATED = "not_demonstrated"
}

obj EvidenceRecord {
    has record_id: str;
    has kind: str;
    has text: str;
}

sem EvidenceRecord.record_id = "T1, T2... for things the candidate said, C1, C2... for code snapshots";
sem EvidenceRecord.kind = "'said' for something the candidate said, 'code' for a code snapshot";

obj DimensionGrade {
    has status: EvidenceStatus;
    has score: int;
    has evidence_id: str;
    has excerpt: str;
    has comment: str;
    has practice_suggestion: str;
}

sem DimensionGrade.status = "SCORED if the candidate's own words or code give evidence for this area. NOT_DEMONSTRATED if they gave none. Silence, filler, or 'I don't know' is not evidence.";
sem DimensionGrade.score = "1 to 5 when SCORED, 0 when NOT_DEMONSTRATED";
sem DimensionGrade.evidence_id = "The record_id of the single best candidate record supporting the score. Empty when NOT_DEMONSTRATED. Never an interviewer line.";
sem DimensionGrade.excerpt = "3 to 20 words copied word for word from that record. No paraphrasing, no added words; a program checks it. Empty when NOT_DEMONSTRATED.";
sem DimensionGrade.comment = "One or two plain sentences to the candidate as 'you', explaining the score or what was missing";
sem DimensionGrade.practice_suggestion = "One concrete thing to practice next for this area";

obj GradeReport {
    has understanding: DimensionGrade;
    has approach: DimensionGrade;
    has correctness: DimensionGrade;
    has complexity: DimensionGrade;
    has code: DimensionGrade;
    has summary: str;
    has strengths: list[str];
    has improvements: list[str];
}

sem GradeReport.summary = "Two sentences to the candidate";
sem GradeReport.strengths = "Up to three real strengths; empty if there's nothing real to praise";
sem GradeReport.improvements = "Up to three specific improvements";

# ---------- The two model calls ----------

def grade_interview(
    question: str,
    candidate_records: list[EvidenceRecord],
    interviewer_lines: list[str],
    hints_used: int
) -> GradeReport by llm(temperature=0.0);

sem grade_interview = """Grade a mock coding interview after it ended, in five areas:
- understanding: did they restate the problem, ask clarifying questions, and notice constraints and edge cases (empty input, duplicates, negatives)?
- approach: did they explain their thinking clearly and in order, and compare at least one alternative?
- correctness: would the solution they described or wrote actually work, including edge cases?
- complexity: did they state the time and space complexity and justify it from how the solution works?
- code: only from READING their code snapshots, is it readable and does it match the approach they described? NOT_DEMONSTRATED if they wrote no code.
For each area, use SCORED only if the candidate's own words or code give evidence. Otherwise use NOT_DEMONSTRATED.
Silence, filler, or "I don't know" is not evidence: a candidate who never discussed complexity gets NOT_DEMONSTRATED
for complexity, not a low score.
The candidate spoke out loud, so their words come from speech-to-text: ignore filler words, restarts, and misspelled
technical terms. Only candidate_records can be cited; interviewer_lines are context only.
Credit ideas the candidate reached on their own more than ideas a hint handed them.
You did not run any code. Describe code only from reading it, and never claim it passed tests, produced output,
or was executed.""";

def regrade_interview(
    question: str,
    candidate_records: list[EvidenceRecord],
    interviewer_lines: list[str],
    hints_used: int,
    failed_citations: list[str]
) -> GradeReport by llm(temperature=0.0);

sem regrade_interview = """Grade the interview again in the same five areas (understanding, approach, correctness,
complexity, code). Your last grade failed an automatic citation check; failed_citations says which areas and why.
For those areas, copy the excerpt exactly from the cited candidate record, or use NOT_DEMONSTRATED if no record
supports a score. Same rules as before: silence or filler is not evidence, only candidate_records are citable,
judge code only from reading it, and never claim the code was run.""";

# ---------- Citation check (plain code, no model) ----------

obj CitationCheck {
    has verified: bool;
    has reason: str;
}

glob dimension_names: list[str] = ["understanding", "approach", "correctness", "complexity", "code"];

def normalize_for_matching(text: str) -> str {
    normalized = text.lower();
    normalized = normalized.replace("‘", "'").replace("’", "'");
    normalized = normalized.replace("“", "\"").replace("”", "\"");
    return " ".join(normalized.split());
}

def trim_edge_punctuation(text: str) -> str {
    return text.strip(" \"'.,;:…-");
}

def find_record(candidate_records: list[EvidenceRecord], record_id: str) -> EvidenceRecord | None {
    for record in candidate_records {
        if record.record_id == record_id {
            return record;
        }
    }
    return None;
}

def check_citation(candidate_records: list[EvidenceRecord], grade: DimensionGrade) -> CitationCheck {
    if grade.status == EvidenceStatus.NOT_DEMONSTRATED {
        return CitationCheck(verified=True, reason="");
    }
    evidence_id = grade.evidence_id.strip();
    record = find_record(candidate_records, evidence_id);
    if record is None {
        return CitationCheck(
            verified=False,
            reason="It cited '" + evidence_id + "', but there is no candidate turn or code snapshot with that ID."
        );
    }
    excerpt = trim_edge_punctuation(normalize_for_matching(grade.excerpt));
    if len(excerpt) < 3 {
        return CitationCheck(verified=False, reason="It cited " + evidence_id + " without quoting anything from it.");
    }
    if excerpt not in normalize_for_matching(record.text) {
        return CitationCheck(verified=False, reason="The quoted excerpt doesn't appear in " + evidence_id + ".");
    }
    return CitationCheck(verified=True, reason="");
}

def get_dimension(grade_report: GradeReport, dimension_name: str) -> DimensionGrade {
    if dimension_name == "understanding" {
        return grade_report.understanding;
    } elif dimension_name == "approach" {
        return grade_report.approach;
    } elif dimension_name == "correctness" {
        return grade_report.correctness;
    } elif dimension_name == "complexity" {
        return grade_report.complexity;
    }
    return grade_report.code;
}

def check_all_citations(candidate_records: list[EvidenceRecord], grade_report: GradeReport) -> dict[str, CitationCheck] {
    checks: dict[str, CitationCheck] = {};
    for dimension_name in dimension_names {
        checks[dimension_name] = check_citation(candidate_records, get_dimension(grade_report, dimension_name));
    }
    return checks;
}

def list_failed_checks(checks: dict[str, CitationCheck]) -> list[str] {
    failures: list[str] = [];
    for dimension_name in dimension_names {
        if not checks[dimension_name].verified {
            failures.append(dimension_name + ": " + checks[dimension_name].reason);
        }
    }
    return failures;
}

# ---------- Putting it together ----------

obj CheckedGrade {
    has grade_report: GradeReport;
    has checks: dict[str, CitationCheck];
    has used_retry: bool;
}

def not_demonstrated(comment: str) -> DimensionGrade {
    return DimensionGrade(
        status=EvidenceStatus.NOT_DEMONSTRATED,
        score=0,
        evidence_id="",
        excerpt="",
        comment=comment,
        practice_suggestion="Practice thinking out loud from the first minute, even if it's just restating the problem."
    );
}

"""When the candidate never said or wrote anything, there's nothing to cite, so skip the model."""
def build_silent_report -> GradeReport {
    comment = "You didn't say or write anything for this area, so there's nothing to grade.";
    return GradeReport(
        understanding=not_demonstrated(comment),
        approach=not_demonstrated(comment),
        correctness=not_demonstrated(comment),
        complexity=not_demonstrated(comment),
        code=not_demonstrated(comment),
        summary="The interview ended before you answered, so every area is marked not demonstrated.",
        strengths=[],
        improvements=["Start by restating the problem and naming a brute-force approach, even before you have the best one."]
    );
}

def grade_with_citation_checks(
    question: str,
    candidate_records: list[EvidenceRecord],
    interviewer_lines: list[str],
    hints_used: int
) -> CheckedGrade {
    if len(candidate_records) == 0 {
        silent_report = build_silent_report();
        return CheckedGrade(
            grade_report=silent_report,
            checks=check_all_citations(candidate_records, silent_report),
            used_retry=False
        );
    }
    first_report = grade_interview(question, candidate_records, interviewer_lines, hints_used);
    first_checks = check_all_citations(candidate_records, first_report);
    failures = list_failed_checks(first_checks);
    if len(failures) == 0 {
        return CheckedGrade(grade_report=first_report, checks=first_checks, used_retry=False);
    }
    second_report = regrade_interview(question, candidate_records, interviewer_lines, hints_used, failures);
    return CheckedGrade(
        grade_report=second_report,
        checks=check_all_citations(candidate_records, second_report),
        used_retry=True
    );
}

# ---------- Loading a transcript and printing the report ----------

obj Transcript {
    has question: str;
    has candidate_records: list[EvidenceRecord];
    has interviewer_lines: list[str];
    has hints_used: int;
}

"""Reads the JSON the web app's "Copy transcript for Jac grader" button produces."""
def load_transcript(file_path: str) -> Transcript {
    with open(file_path) as transcript_file {
        data = json.load(transcript_file);
    }
    candidate_records: list[EvidenceRecord] = [];
    for raw_record in data["candidate_records"] {
        candidate_records.append(
            EvidenceRecord(
                record_id=str(raw_record["record_id"]),
                kind=str(raw_record["kind"]),
                text=str(raw_record["text"])
            )
        );
    }
    interviewer_lines: list[str] = [];
    if "interviewer_lines" in data {
        for raw_line in data["interviewer_lines"] {
            interviewer_lines.append(str(raw_line));
        }
    }
    hints_used = 0;
    if "hints_used" in data {
        hints_used = int(data["hints_used"]);
    }
    return Transcript(
        question=str(data["question"]),
        candidate_records=candidate_records,
        interviewer_lines=interviewer_lines,
        hints_used=hints_used
    );
}

def format_report(checked: CheckedGrade, candidate_records: list[EvidenceRecord]) -> str {
    lines: list[str] = [];
    total_points = 0;
    for dimension_name in dimension_names {
        grade = get_dimension(checked.grade_report, dimension_name);
        check = checked.checks[dimension_name];
        title = dimension_name.upper();
        if not check.verified {
            lines.append(title + ": NOT SHOWN (citation failed: " + check.reason + ")");
        } elif grade.status == EvidenceStatus.NOT_DEMONSTRATED {
            lines.append(title + ": not demonstrated");
            lines.append("  " + grade.comment);
            lines.append("  Practice next: " + grade.practice_suggestion);
        } else {
            score = max(1, min(5, grade.score));
            total_points = total_points + score;
            source_label = "you said";
            record = find_record(candidate_records, grade.evidence_id.strip());
            if record is not None and record.kind == "code" {
                source_label = "your code, read not run";
            }
            lines.append(title + ": " + str(score) + " / 5");
            lines.append("  [" + grade.evidence_id + ", " + source_label + "] \"" + grade.excerpt + "\"");
            lines.append("  " + grade.comment);
            lines.append("  Practice next: " + grade.practice_suggestion);
        }
        lines.append("");
    }
    header = "TOTAL: " + str(total_points) + " / 25";
    if checked.used_retry {
        header = header + "  (grader needed one retry to fix its citations)";
    }
    lines.insert(0, "");
    lines.insert(0, checked.grade_report.summary);
    lines.insert(0, header);
    return "\n".join(lines);
}

with entry:__main__ {
    if len(sys.argv) < 2 {
        print("Usage: jac run grader.jac <transcript.json>");
    } else {
        transcript = load_transcript(sys.argv[-1]);
        checked = grade_with_citation_checks(
            transcript.question,
            transcript.candidate_records,
            transcript.interviewer_lines,
            transcript.hints_used
        );
        print(format_report(checked, transcript.candidate_records));
    }
}
