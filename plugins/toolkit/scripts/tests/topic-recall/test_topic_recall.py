"""Behavior tests for topic-recall.py. Run through run-tests.sh."""
from __future__ import annotations

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from typing import Any, List, Optional

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "topic-recall.py")
INDEXER = os.path.join(os.path.dirname(SCRIPT), "vault-index.py")
ROOT_FOLDER = os.path.join("AI", "Claude-Code")

_spec = importlib.util.spec_from_file_location("topic_recall", SCRIPT)
tr = importlib.util.module_from_spec(_spec)
sys.modules["topic_recall"] = tr
_spec.loader.exec_module(tr)

PLAIN_ROW = "- [[3D Secure]] — 3D Secure authenticates card payments. (shop-a, shop-b; unverified)"
STALE_ROW = "- [[tenant-hub-identity]] — tenant-hub splits tenant identity. (tenant-hub; verified 2026-08-10; ⚠ stale)"
REPOLESS_UNVERIFIED_ROW = "- [[Solo Note]] — Solo note has no repos. (unverified)"
REPOLESS_VERIFIED_ROW = "- [[Solo Note]] — Solo note has no repos. (verified 2026-08-10)"
REPOLESS_STALE_ROW = "- [[Solo Note]] — Solo note has no repos. (verified 2026-08-10; ⚠ stale)"
SHOP_ROW = "- [[Widget Cache]] — Widget cache keeps rendered widgets. (shop; unverified)"
PROJECT_ROW = "- [[plan - example-feature]] — Example plan. (claude-toolkit; unverified)"
TOPIC_NOTE = """---
type: topic
summary: Widget cache keeps rendered widgets for one hour.
domain: general
verified: 2026-09-01
repos:
  - shop
  - shop-api
---

## Overview
"""
GADGET_NOTE = """---
type: topic
summary: Gadget board lists every gadget.
repos: [shop]
---
"""
ODD_NOTE = """---
type: topic
summary: Odd title note.
---
"""
PLAN_NOTE = """---
type: plan
summary: Not a topic.
---
"""


def temp_dir(test: unittest.TestCase) -> str:
    path = tempfile.mkdtemp()
    test.addCleanup(shutil.rmtree, path)
    return path


def write_config(home: str, name: str, vault: str) -> None:
    with open(os.path.join(home, ".claude", name), "w", encoding="utf-8") as fh:
        json.dump({"vault_path": vault, "root_folder": ROOT_FOLDER}, fh)


def make_vault(test: unittest.TestCase, files: dict[str, str]) -> tuple[str, str]:
    """Return (home, root) for a temp HOME whose toolkit-vault.json points at a temp vault."""
    base = temp_dir(test)
    home = os.path.join(base, "home")
    vault = os.path.join(base, "vault")
    root = os.path.join(vault, ROOT_FOLDER)
    os.makedirs(os.path.join(home, ".claude"))
    os.makedirs(root)
    write_config(home, "toolkit-vault.json", vault)
    for rel, body in files.items():
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(body)
    return home, root


def index(*rows: str, projects: str = "") -> str:
    return "# Vault index\n\n## Topics by domain\n\n### general\n\n" + "\n".join(rows) + f"\n\n## Projects\n\n{projects}\n"


def run_cli(home: str, *args: str, cwd: Optional[str] = None, script: str = SCRIPT) -> subprocess.CompletedProcess:
    env = {"HOME": home, "PATH": os.environ.get("PATH", "")}
    return subprocess.run([sys.executable, "-I", script, *args], env=env, cwd=cwd,
                          capture_output=True, text=True, timeout=10)


def run_indexer(root: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, "-I", INDEXER, root], capture_output=True, text=True, timeout=10)


def read_bytes(path: str) -> bytes:
    with open(path, "rb") as fh:
        return fh.read()


def touch_after(index_path: str, *paths: str) -> None:
    """Set each path's modification time one second after the index's."""
    later = os.stat(index_path).st_mtime_ns + 1_000_000_000
    for path in paths:
        os.utime(path, ns=(later, later))


def titles(result: subprocess.CompletedProcess) -> List[str]:
    return [row["title"] for row in json.loads(result.stdout)]


def candidate(title: str, summary: str = "", repos: Optional[List[str]] = None) -> Any:
    return tr.Candidate(title=title, summary=summary, repos=repos or [], verified="unverified", stale=False)


def make_repo(test: unittest.TestCase, files: dict[str, str]) -> str:
    """Return the root of a temp repo named shop whose docs/ holds the given files."""
    repo = os.path.join(temp_dir(test), "shop")
    for rel, body in files.items():
        path = os.path.join(repo, "docs", rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(body)
    return repo


def write_file(path: str, body: str) -> str:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(body)
    return path


def chdir(test: unittest.TestCase, path: str) -> None:
    test.addCleanup(os.chdir, os.getcwd())
    os.chdir(path)


def numbered_docs(count: int) -> dict[str, str]:
    return {f"doc-{n:03d}.md": f"# Doc {n:03d}\n" for n in range(1, count + 1)}


def long_frontmatter(summary: str, extra_lines: int) -> str:
    refs = "".join(f"  - ref-{n}.md\n" for n in range(extra_lines))
    return f"---\ntitle: Long Note\nsummary: {summary}\nsource_refs:\n{refs}---\n\nBody paragraph.\n"


class TopicRecallTest(unittest.TestCase):
    def test_plain_row_parses_into_candidate(self):
        _home, root = make_vault(self, {"INDEX.md": index(PLAIN_ROW)})

        rows = tr.read_index(os.path.join(root, "INDEX.md"))

        self.assertEqual(rows, [tr.Candidate(
            title="3D Secure", summary="3D Secure authenticates card payments.",
            repos=["shop-a", "shop-b"], verified="unverified", stale=False)])

    def test_stale_row_keeps_verified_and_sets_stale(self):
        _home, root = make_vault(self, {"INDEX.md": index(STALE_ROW)})

        row = tr.read_index(os.path.join(root, "INDEX.md"))[0]

        self.assertEqual((row.verified, row.stale), ("verified 2026-08-10", True))

    def test_section_boundary_excludes_projects_rows(self):
        _home, root = make_vault(self, {"INDEX.md": index(PLAIN_ROW, projects=PROJECT_ROW)})

        rows = tr.read_index(os.path.join(root, "INDEX.md"))

        self.assertEqual([row.title for row in rows], ["3D Secure"])

    def test_title_hit_outranks_summary_hit(self):
        rows = [candidate("Other Note", summary="mentions widget once"), candidate("Widget Cache")]

        ranked = tr.rank(rows, ["widget"], None)

        self.assertEqual([cand.title for _score, cand in ranked], ["Widget Cache", "Other Note"])

    def test_repo_boost_applies(self):
        rows = [candidate("Widget Cache", repos=["shop"])]

        ranked = tr.rank(rows, [], "shop")

        self.assertEqual([score for score, _cand in ranked], [tr.REPO_MATCH])

    def test_zero_score_rows_are_dropped(self):
        rows = [candidate("Widget Cache"), candidate("Payment Recovery")]

        ranked = tr.rank(rows, ["widget"], "shop")

        self.assertEqual([cand.title for _score, cand in ranked], ["Widget Cache"])

    def test_missing_index_falls_back_to_scan(self):
        home, _root = make_vault(self, {"Projects/shop/Widget Cache.md": TOPIC_NOTE})

        result = run_cli(home, "--repo", "shop")

        self.assertEqual(result.stdout.splitlines()[0], tr.FALLBACK_HEADER, result.stderr)

    def test_scan_reads_topic_frontmatter(self):
        _home, root = make_vault(self, {"Projects/shop/Widget Cache.md": TOPIC_NOTE, "Projects/shop/plan - x.md": PLAN_NOTE})

        rows = tr.scan_topics(root)

        self.assertEqual(rows, [tr.Candidate(
            title="Widget Cache", summary="Widget cache keeps rendered widgets for one hour.",
            repos=["shop", "shop-api"], verified="verified 2026-09-01", stale=False,
            path=os.path.join(root, "Projects", "shop", "Widget Cache.md"))])

    def test_evicted_note_renders_with_blank_path(self):
        home, _root = make_vault(self, {"INDEX.md": index(PLAIN_ROW), "Projects/shop-a/.3D Secure.md.icloud": ""})

        result = run_cli(home, "--repo", "shop-a")

        self.assertEqual(result.stdout, (
            "3D Secure [shop-a, shop-b] [vault] (unverified) (score 6)\n"
            "  3D Secure authenticates card payments.\n"
            "  (no local file)\n"), result.stderr)

    def test_top_truncates(self):
        home, _root = make_vault(self, {"INDEX.md": index(PLAIN_ROW, STALE_ROW)})

        result = run_cli(home, "--top", "1", "--format", "json", "secure", "identity")

        self.assertEqual(len(json.loads(result.stdout)), 1, result.stderr)

    def test_json_shape(self):
        home, _root = make_vault(self, {"INDEX.md": index(STALE_ROW)})

        result = run_cli(home, "--repo", "tenant-hub", "--format", "json")

        self.assertEqual(json.loads(result.stdout), [{
            "title": "tenant-hub-identity", "summary": "tenant-hub splits tenant identity.", "repos": ["tenant-hub"],
            "verified": "verified 2026-08-10", "stale": True, "path": "", "source": "vault",
            "score": tr.REPO_MATCH}], result.stderr)

    def test_missing_config_exits_2(self):
        home = temp_dir(self)

        result = run_cli(home, "anything")

        self.assertEqual(result.returncode, 2, result.stderr)

    def test_legacy_config_alone_resolves_the_vault(self):
        home, _root = make_vault(self, {"INDEX.md": index(SHOP_ROW)})
        claude = os.path.join(home, ".claude")
        os.rename(os.path.join(claude, "toolkit-vault.json"), os.path.join(claude, "obsidian-sync.json"))

        result = run_cli(home, "--repo", "shop", "--format", "json")

        self.assertEqual([row["title"] for row in json.loads(result.stdout)], ["Widget Cache"], result.stderr)

    def test_new_config_alone_resolves_the_vault(self):
        home, _root = make_vault(self, {"INDEX.md": index(SHOP_ROW)})

        result = run_cli(home, "--repo", "shop", "--format", "json")

        self.assertEqual([row["title"] for row in json.loads(result.stdout)], ["Widget Cache"], result.stderr)

    def test_new_config_wins_over_legacy_config(self):
        home, _root = make_vault(self, {"INDEX.md": index(SHOP_ROW)})
        other = os.path.join(temp_dir(self), "vault")
        write_file(os.path.join(other, ROOT_FOLDER, "INDEX.md"), index(PLAIN_ROW))
        write_config(home, "obsidian-sync.json", other)

        result = run_cli(home, "--repo", "shop", "--format", "json")

        self.assertEqual([row["title"] for row in json.loads(result.stdout)], ["Widget Cache"], result.stderr)

    def test_invalid_new_config_exits_2_beside_valid_legacy_config(self):
        home, root = make_vault(self, {"INDEX.md": index(SHOP_ROW)})
        write_config(home, "obsidian-sync.json", os.path.dirname(os.path.dirname(root)))
        write_file(os.path.join(home, ".claude", "toolkit-vault.json"), '{"vault_path": ')

        result = run_cli(home, "--repo", "shop")

        self.assertEqual(result.returncode, 2, result.stderr)

    def test_version_prints_the_resolved_version_without_config(self):
        home = temp_dir(self)

        result = run_cli(home, "--version")

        self.assertEqual((result.returncode, result.stdout), (0, tr.content_version(tr.PLUGIN_ROOT) + "\n"), result.stderr)

    def test_version_prints_the_install_folder_name_from_the_cache(self):
        scripts = os.path.join(temp_dir(self), "cache", "example-market", "toolkit", "0123456789ab", "scripts")
        os.makedirs(scripts)
        shutil.copy(SCRIPT, scripts)

        result = run_cli(temp_dir(self), "--version", script=os.path.join(scripts, "topic-recall.py"))

        self.assertEqual((result.returncode, result.stdout), (0, "0123456789ab\n"), result.stderr)

    def test_repo_doc_title_comes_from_h1_without_frontmatter(self):
        repo = make_repo(self, {"cache.md": "# Widget cache\n\nKeeps widgets.\n"})

        rows = tr.scan_repo_docs(repo)

        self.assertEqual([row.title for row in rows], ["Widget cache"])

    def test_repo_doc_summary_skips_managed_by_comment(self):
        repo = make_repo(self, {"cache.md": "# Widget cache\n<!-- managed-by: toolkit -->\n\nKeeps widgets for one hour.\n"})

        rows = tr.scan_repo_docs(repo)

        self.assertEqual([row.summary for row in rows], ["Keeps widgets for one hour."])

    def test_frontmatter_closing_late_within_scan_lines_yields_summary(self):
        repo = make_repo(self, {"long.md": long_frontmatter("Frontmatter summary.", tr.SCAN_LINES - 10)})

        rows = tr.scan_repo_docs(repo)

        self.assertEqual([row.summary for row in rows], ["Frontmatter summary."])

    def test_docs_readme_outranks_sibling_on_equal_hits(self):
        repo = make_repo(self, {"README.md": "# Shop docs\n", "api.md": "# Shop API\n"})

        ranked = tr.rank(tr.scan_repo_docs(repo), ["shop"], "shop", tr.docs_index_path(repo))

        self.assertEqual([cand.title for _score, cand in ranked], ["Shop docs", "Shop API"])

    def test_file_at_depth_5_is_excluded(self):
        repo = make_repo(self, {"a/b/c/four.md": "# Four\n", "a/b/c/d/five.md": "# Five\n"})

        rows = tr.scan_repo_docs(repo)

        self.assertEqual([row.title for row in rows], ["Four"])

    def test_401st_file_is_excluded(self):
        repo = make_repo(self, numbered_docs(tr.REPO_MAX_FILES + 1))

        rows = tr.scan_repo_docs(repo)

        self.assertEqual(rows[-1].title, "Doc 400")

    def test_repo_root_without_docs_yields_vault_rows_only(self):
        home, _root = make_vault(self, {"INDEX.md": index(STALE_ROW)})
        repo = temp_dir(self)

        result = run_cli(home, "--repo", "tenant-hub", "--repo-root", repo, "--format", "json")

        self.assertEqual({row["source"] for row in json.loads(result.stdout)}, {"vault"}, result.stderr)

    def test_repo_less_unverified_row_parses(self):
        row = tr.parse_row(REPOLESS_UNVERIFIED_ROW)

        self.assertEqual(row, tr.Candidate(
            title="Solo Note", summary="Solo note has no repos.", repos=[], verified="unverified", stale=False))

    def test_repo_named_like_the_stale_marker_is_a_repo(self):
        row = tr.parse_row("- [[Bot Note]] — Bot note. (stalebot; unverified)")

        self.assertEqual((row.repos, row.stale), (["stalebot"], False))

    def test_repo_less_verified_row_parses(self):
        row = tr.parse_row(REPOLESS_VERIFIED_ROW)

        self.assertEqual((row.repos, row.verified, row.stale), ([], "verified 2026-08-10", False))

    def test_repo_less_stale_row_parses(self):
        row = tr.parse_row(REPOLESS_STALE_ROW)

        self.assertEqual((row.repos, row.verified, row.stale), ([], "verified 2026-08-10", True))

    def test_repo_docs_without_token_hit_are_dropped(self):
        repo = make_repo(self, {"README.md": "# Shop docs\n", "api.md": "# Shop API\n"})

        ranked = tr.rank(tr.scan_repo_docs(repo), ["xyzzy"], "shop", tr.docs_index_path(repo))

        self.assertEqual(ranked, [])

    def test_empty_query_returns_no_repo_rows(self):
        repo = make_repo(self, {"README.md": "# Shop docs\n", "api.md": "# Shop API\n"})

        ranked = tr.rank(tr.scan_repo_docs(repo), [], "shop", tr.docs_index_path(repo))

        self.assertEqual(ranked, [])

    def test_symlinked_repo_doc_is_skipped(self):
        repo = make_repo(self, {"real.md": "# Real\n"})
        outside = write_file(os.path.join(temp_dir(self), "outside.md"), "# Outside\n")
        os.symlink(outside, os.path.join(repo, "docs", "link.md"))

        rows = tr.scan_repo_docs(repo)

        self.assertEqual([row.title for row in rows], ["Real"])

    def test_symlinked_docs_subdirectory_is_pruned(self):
        repo = make_repo(self, {"real.md": "# Real\n"})
        outside = temp_dir(self)
        write_file(os.path.join(outside, "outside.md"), "# Outside\n")
        os.symlink(outside, os.path.join(repo, "docs", "linked"))

        rows = tr.scan_repo_docs(repo)

        self.assertEqual([row.title for row in rows], ["Real"])

    def test_symlinked_topic_note_is_skipped(self):
        _home, root = make_vault(self, {"Projects/shop/Widget Cache.md": TOPIC_NOTE})
        outside = write_file(os.path.join(temp_dir(self), "Other.md"), TOPIC_NOTE)
        os.symlink(outside, os.path.join(root, "Projects", "shop", "Other.md"))

        rows = tr.scan_topics(root)

        self.assertEqual([row.title for row in rows], ["Widget Cache"])

    def test_single_200k_line_is_read_within_the_cap(self):
        repo = make_repo(self, {"wide.md": "x" * (200 * 1024)})

        rows = tr.scan_repo_docs(repo)

        self.assertEqual(len(rows[0].summary), tr.REPO_SUMMARY_CAP)

    @unittest.skipUnless(hasattr(os, "mkfifo"), "needs mkfifo")
    def test_fifo_index_falls_back_to_scan(self):
        home, root = make_vault(self, {"Projects/shop/Widget Cache.md": TOPIC_NOTE})
        os.mkfifo(os.path.join(root, "INDEX.md"))

        result = run_cli(home, "--repo", "shop")

        self.assertEqual(result.stdout.splitlines()[0], tr.FALLBACK_HEADER, result.stderr)

    def test_unreadable_index_names_its_path_on_stderr(self):
        home, root = make_vault(self, {"Projects/shop/Widget Cache.md": TOPIC_NOTE})
        os.makedirs(os.path.join(root, "INDEX.md"))

        result = run_cli(home, "--repo", "shop")

        self.assertIn(os.path.join(root, "INDEX.md"), result.stderr)

    def test_block_scalar_summary_joins_its_lines(self):
        repo = make_repo(self, {"folded.md": "---\nsummary: >-\n  Folded line one\n  and line two.\ntitle: Folded\n---\n"})

        rows = tr.scan_repo_docs(repo)

        self.assertEqual([row.summary for row in rows], ["Folded line one and line two."])

    def test_bom_before_frontmatter_is_ignored(self):
        repo = make_repo(self, {"bom.md": "\ufeff---\ntitle: Bom Title\n---\n"})

        rows = tr.scan_repo_docs(repo)

        self.assertEqual([row.title for row in rows], ["Bom Title"])

    def test_hard_wrapped_paragraph_joins_into_one_summary(self):
        repo = make_repo(self, {"wrap.md": "# Wrap\n\nFirst line\nsecond line.\n\nNext paragraph.\n"})

        rows = tr.scan_repo_docs(repo)

        self.assertEqual([row.summary for row in rows], ["First line second line."])

    def test_frontmatter_unclosed_within_scan_lines_yields_file_name(self):
        repo = make_repo(self, {"long.md": long_frontmatter("Frontmatter summary.", tr.SCAN_LINES + 10)})

        row = tr.scan_repo_docs(repo)[0]

        self.assertEqual((row.title, row.summary), ("long", ""))

    def test_index_without_topic_rows_falls_back_to_scan(self):
        home, _root = make_vault(self, {"INDEX.md": index(), "Projects/shop/Widget Cache.md": TOPIC_NOTE})

        result = run_cli(home, "--repo", "shop")

        self.assertEqual(result.stdout.splitlines()[0], tr.FALLBACK_HEADER, result.stderr)

    def test_two_letter_query_token_is_ignored(self):
        rows = [candidate("Go Widget")]

        ranked = tr.rank(rows, ["go"], None)

        self.assertEqual(ranked, [])

    def test_three_letter_query_token_counts(self):
        rows = [candidate("API Widget")]

        ranked = tr.rank(rows, ["api"], None)

        self.assertEqual([score for score, _cand in ranked], [tr.TITLE_HIT])

    def test_summary_at_cap_is_kept_whole(self):
        paragraph = "y" * tr.REPO_SUMMARY_CAP
        repo = make_repo(self, {"cap.md": f"# Cap\n\n{paragraph}\n"})

        rows = tr.scan_repo_docs(repo)

        self.assertEqual([row.summary for row in rows], [paragraph])

    def test_summary_past_cap_is_cut(self):
        paragraph = "y" * tr.REPO_SUMMARY_CAP + "z"
        repo = make_repo(self, {"cap.md": f"# Cap\n\n{paragraph}\n"})

        rows = tr.scan_repo_docs(repo)

        self.assertEqual([row.summary for row in rows], [paragraph[:tr.REPO_SUMMARY_CAP]])

    def test_vault_root_that_is_a_file_exits_2(self):
        home, root = make_vault(self, {})
        shutil.rmtree(root)
        write_file(root, "not a directory\n")

        result = run_cli(home, "anything")

        self.assertEqual(result.returncode, 2, result.stderr)

    def test_relative_repo_root_names_the_repo(self):
        repo = make_repo(self, {"cache.md": "# Widget cache\n"})
        chdir(self, repo)

        rows = tr.scan_repo_docs(".")

        self.assertEqual([row.repos for row in rows], [["shop"]])

    def test_relative_repo_root_sets_the_repo_default(self):
        home, _root = make_vault(self, {"INDEX.md": index(SHOP_ROW)})
        repo = make_repo(self, {"notes.md": "# Notes\n"})

        result = run_cli(home, "--repo-root", ".", "--format", "json", cwd=repo)

        self.assertEqual([row["title"] for row in json.loads(result.stdout)], ["Widget Cache"], result.stderr)


    def test_generated_index_leaves_recall_output_unchanged(self):
        home, root = make_vault(self, {"Projects/shop/Widget Cache.md": TOPIC_NOTE, "Projects/shop/Gadget Board.md": GADGET_NOTE})
        before = run_cli(home, "--repo", "shop", "--format", "json").stdout
        run_indexer(root)

        after = run_cli(home, "--repo", "shop", "--format", "json").stdout

        self.assertEqual(after, before)

    def test_generated_index_on_unchanged_vault_is_used(self):
        home, root = make_vault(self, {"Projects/shop/Widget Cache.md": TOPIC_NOTE})
        run_indexer(root)

        result = run_cli(home, "--repo", "shop")

        self.assertNotEqual(result.stdout.splitlines()[0], tr.FALLBACK_HEADER, result.stderr)

    def test_generator_keeps_an_index_without_the_marker(self):
        _home, root = make_vault(self, {"INDEX.md": index(SHOP_ROW), "Projects/shop/Gadget Board.md": GADGET_NOTE})
        before = read_bytes(os.path.join(root, "INDEX.md"))

        run_indexer(root)

        self.assertEqual(read_bytes(os.path.join(root, "INDEX.md")), before)

    def test_second_generator_run_keeps_the_bytes(self):
        _home, root = make_vault(self, {"Projects/shop/Widget Cache.md": TOPIC_NOTE})
        run_indexer(root)
        before = read_bytes(os.path.join(root, "INDEX.md"))

        run_indexer(root)

        self.assertEqual(read_bytes(os.path.join(root, "INDEX.md")), before)

    def test_note_written_after_the_index_is_recalled(self):
        home, root = make_vault(self, {"Projects/shop/Widget Cache.md": TOPIC_NOTE})
        run_indexer(root)
        note = write_file(os.path.join(root, "Projects", "shop", "Gadget Board.md"), GADGET_NOTE)
        touch_after(os.path.join(root, "INDEX.md"), note, os.path.dirname(note))

        result = run_cli(home, "--format", "json", "gadget")

        self.assertEqual(titles(result), ["Gadget Board"], result.stderr)

    def test_note_deleted_after_the_index_is_not_recalled(self):
        home, root = make_vault(self, {"Projects/shop/Widget Cache.md": TOPIC_NOTE, "Projects/shop/Gadget Board.md": GADGET_NOTE})
        run_indexer(root)
        os.remove(os.path.join(root, "Projects", "shop", "Gadget Board.md"))
        touch_after(os.path.join(root, "INDEX.md"), os.path.join(root, "Projects", "shop"))

        result = run_cli(home, "--format", "json", "gadget")

        self.assertEqual(titles(result), [], result.stderr)

    def test_note_edited_in_place_after_the_index_is_recalled_with_its_new_summary(self):
        home, root = make_vault(self, {"Projects/shop/Widget Cache.md": TOPIC_NOTE})
        run_indexer(root)
        note = write_file(os.path.join(root, "Projects", "shop", "Widget Cache.md"),
                          TOPIC_NOTE.replace("for one hour", "for one day"))
        touch_after(os.path.join(root, "INDEX.md"), note)

        result = run_cli(home, "--format", "json", "widget")

        self.assertEqual([row["summary"] for row in json.loads(result.stdout)],
                         ["Widget cache keeps rendered widgets for one day."], result.stderr)

    def test_older_index_without_the_marker_still_supplies_rows(self):
        home, root = make_vault(self, {"INDEX.md": index(PLAIN_ROW), "Projects/shop/Widget Cache.md": TOPIC_NOTE})
        touch_after(os.path.join(root, "INDEX.md"), os.path.join(root, "Projects", "shop", "Widget Cache.md"))

        result = run_cli(home, "--format", "json", "secure")

        self.assertEqual(titles(result), ["3D Secure"], result.stderr)

    def test_unwritable_title_leaves_no_index(self):
        _home, root = make_vault(self, {"Projects/shop/Odd ] Title.md": ODD_NOTE})

        run_indexer(root)

        self.assertFalse(os.path.lexists(os.path.join(root, "INDEX.md")))

    def test_unwritable_title_is_named_on_stderr(self):
        _home, root = make_vault(self, {"Projects/shop/Odd ] Title.md": ODD_NOTE})

        result = run_indexer(root)

        self.assertIn(os.path.join(root, "Projects", "shop", "Odd ] Title.md"), result.stderr)

    def test_unwritable_title_is_still_recalled(self):
        home, root = make_vault(self, {"Projects/shop/Odd ] Title.md": ODD_NOTE})
        run_indexer(root)

        result = run_cli(home, "--format", "json", "odd")

        self.assertEqual(titles(result), ["Odd ] Title"], result.stderr)

    def test_shared_title_leaves_no_index(self):
        _home, root = make_vault(self, {"Projects/shop/Widget Cache.md": TOPIC_NOTE, "Docs/Widget Cache.md": TOPIC_NOTE})

        run_indexer(root)

        self.assertFalse(os.path.lexists(os.path.join(root, "INDEX.md")))

    def test_shared_title_recall_holds_both_paths(self):
        home, root = make_vault(self, {"Projects/shop/Widget Cache.md": TOPIC_NOTE, "Docs/Widget Cache.md": TOPIC_NOTE})
        run_indexer(root)

        result = run_cli(home, "--format", "json", "widget")

        self.assertEqual({row["path"] for row in json.loads(result.stdout)},
                         {os.path.join(root, "Projects", "shop", "Widget Cache.md"), os.path.join(root, "Docs", "Widget Cache.md")},
                         result.stderr)


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(TopicRecallTest)
    outcome = unittest.TextTestRunner(verbosity=2).run(suite)
    failed = len(outcome.failures) + len(outcome.errors)
    print(f"RESULT: {outcome.testsRun - failed - len(outcome.skipped)} passed, {failed} failed")
    sys.exit(1 if failed else 0)
