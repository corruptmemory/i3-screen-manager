# VCS Comparison: Git+LFS vs Fossil vs SVN

Technical analysis for choosing a version control system for projects with significant binary/large-file content.

---

## Quick Reference

| Aspect | Git + git-lfs | Fossil | SVN |
|--------|--------------|--------|-----|
| **Architecture** | Distributed | Distributed | Centralized |
| **Binary file handling** | Poor natively; LFS bolts on | Adequate for small/medium | Excellent — native delta compression |
| **File locking** | LFS only, bolted on | None | Native, enforced via `svn:needs-lock` |
| **Branch management** | Lightweight, instant | Tag-based, autosync'd | Directory copies, heavyweight |
| **Merge quality** | Excellent (ort strategy) | Good, always no-ff | Good, improved since 1.5+ |
| **Self-hosting** | Complex (needs Gitea/GitLab/etc.) | Trivial — single binary, CGI | Moderate (Apache+mod_dav or svnserve) |
| **Repo robustness** | SHA-1 integrity, reactive `fsck` | SQLite ACID, proactive verification | MD5 checksums, decent |
| **Ease of use** | Steep curve, powerful | Gentle curve, simpler | Easiest for newcomers |
| **Ecosystem** | Dominant (~94% adoption) | Niche, self-contained | Legacy but still active |

---

## 1. Distributed Development

### Git
Full DVCS. Every clone has complete history. Work offline, commit locally, push when ready. The gold standard for distributed open-source development. Supports multiple remotes, forks, and complex multi-party workflows natively.

### Fossil
Full DVCS with a twist: **autosync is on by default**. Commits automatically push to the remote, so in practice it behaves like a centralized system with distributed backup. You *can* turn autosync off for offline work, but the design philosophy is "everybody shares everything" — all branches, all tickets, all wiki pages sync globally. No cherry-picking which branches to push.

### SVN
Centralized. Every commit requires server connectivity. No offline commits, no local branching. The server is the single source of truth. This is a feature, not a bug, for teams that want one authoritative state with clear audit trails.

`★ Insight ─────────────────────────────────────`
- Fossil's autosync is the philosophical middle ground: you get distributed *storage* (every clone is a full backup) but centralized *workflow* (commits flow upstream immediately). This matches how most teams actually work — even Git teams typically maintain a central "origin" they push to regularly.
- SVN's centralized model is an advantage in regulated industries (finance, aerospace) where you need an immutable, auditable chain of custody. Git's ability to rewrite history is a liability in those contexts.
`─────────────────────────────────────────────────`

---

## 2. Branch Management

### Git
Branches are lightweight pointers to commits — creating one is instant, costs nothing. This encourages short-lived feature branches, which is the basis of GitFlow, GitHub Flow, and trunk-based development. Extremely flexible but demands discipline; it's easy to end up with a tangled mess of stale branches.

### Fossil
Branches are **tags on check-ins**, not separate ref pointers. When you commit with `--branch foo`, Fossil attaches a `branch=foo` tag that propagates forward. Key difference: Fossil actively **prevents accidental forks**. If your commit would diverge from the branch tip (because someone else committed while you were working), Fossil aborts and tells you to merge first. This keeps history more linear by default.

All branches sync globally — you can't keep a branch private to your clone. Experimental work on a branch is immediately visible to everyone. This is great for cross-platform testing (check out the branch on another machine) but bad for "I'm not ready to show this yet."

### SVN
Branches are **directory copies** (`svn copy trunk branches/feature-x`). Physically expensive, conceptually simple. This naturally discourages creating many branches, so SVN teams typically maintain a small number of long-lived branches (trunk, release branches, a few feature branches). Merge tracking via `svn:mergeinfo` (since SVN 1.5) records which changesets have been applied, preventing duplicate merges.

`★ Insight ─────────────────────────────────────`
- Git's "branches are cheap" philosophy is both its greatest strength and biggest source of complexity. Teams need explicit branching strategies (and the discipline to follow them) or things degrade fast.
- Fossil's "would fork" error is intentionally restrictive — it forces you to integrate others' work before committing. This is annoying for solo work but prevents the divergence headaches that plague Git teams who forget to pull before pushing.
- SVN's directory-copy branches mean that `svn log` on a branch shows you exactly what happened on that branch. In Git, untangling branch history after complex merges can be surprisingly difficult.
`─────────────────────────────────────────────────`

---

## 3. Large File / Binary File Handling

This is the core question, and where the systems diverge most dramatically.

### Git (native)
**Terrible for large binaries.** Every clone downloads the entire history of every file. A 2 GB texture that's been modified 50 times means every developer downloads ~100 GB of texture history (minus whatever delta compression achieves). Git's pack format does attempt binary delta compression across all objects, but compressed media formats (PNG, JPEG, MP3, H.264) are already entropy-coded, so deltas achieve only 5-15% savings. Unstructured binary formats are worst-case.

Blender Studio benchmarks: a project with their .blend files resulted in a 24.8 GB server repo and 37.7 GB local clone. SVN for the same content: 38.7 GB server, 26.5 GB local checkout (SVN wins on client-side because you only get the current version).

### Git + git-lfs
LFS replaces large files in the Git repo with tiny pointer files, storing the actual content on a separate LFS server. This means:
- **Clones are fast** — you only download pointer files, not history
- **Checkout downloads on demand** — only the current version's blobs
- **No delta compression** — each version is stored as a complete file on the LFS server

The trade-off: LFS server storage grows linearly with every version (no deltas), so the server side is larger than both SVN and native Git. Blender's test: ~110 GB on the LFS server vs 38.7 GB for SVN. But per-developer storage drops dramatically to 5-15 GB.

**LFS file locking** exists but it's bolted on. `git lfs lock <file>` creates a lock on the LFS server. Other devs see it with `git lfs locks`. It works, but it's not enforced at the filesystem level like SVN's `svn:needs-lock` (which makes files read-only until locked). You're relying on convention and team discipline.

### Fossil
Stores everything in a single SQLite database. Binary files are delta-compressed within the database. Adequate for small-to-medium binary content but **does not scale to large repos**. Fossil's manifest format lists all files in each check-in, creating O(n) overhead that becomes painful with hundreds of thousands of files or multi-GB repos. No file locking mechanism.

Fossil's creator (D. Richard Hipp, also the creator of SQLite) explicitly acknowledges this limitation — Fossil was designed for projects like SQLite itself, not for game studios.

### SVN
**The best native binary file handling of the three.** SVN applies binary delta compression server-side, stores only deltas between versions, and clients check out only the current revision. Key advantages:

- **Binary delta compression** actually works well: SVN's algorithm finds byte-level similarities even in binary formats. 50% compression on structured binary formats (3D models, .blend files) is typical.
- **Sparse checkout**: `svn checkout --depth=files` lets you grab only the directories you need. A level designer doesn't need to download the audio department's assets.
- **Native file locking** via `svn lock` + `svn:needs-lock` property. Files marked with `svn:needs-lock` are read-only until explicitly locked. Your 3D modeling app refuses to open the file for editing, reminding you to lock it first. This is **enforced at the OS filesystem level**, not by convention.
- **No full-history clone**: developers only have the current revision locally. A 50 GB project means ~25 GB on each dev machine, not 50+ GB of history.

**Storage comparison for a 50 GB asset project (100 versions in history):**

| | SVN | Git (vanilla) | Git + LFS | Fossil |
|---|---|---|---|---|
| Server storage | ~75 GB | ~70 GB | ~110 GB | ~85 GB |
| Per-developer local | ~25 GB | ~37 GB | 5-15 GB | ~85 GB |
| 50-dev team total | ~2.5 TB | ~3.7 TB | ~0.5 TB | ~4.25 TB |
| Clone time | 1-2 hr | 2-6 hr | ~30 min | 1-3 hr |

`★ Insight ─────────────────────────────────────`
- Git-LFS wins on per-developer storage but loses on server storage. It's a trade-off: you pay more on the server to save on every client. For a team of 50 that's a clear win. For a solo dev or small team, SVN is simpler and more efficient overall.
- SVN's `svn:needs-lock` is the killer feature for binary-heavy teams. It prevents the problem rather than trying to resolve it after the fact. You simply cannot have two people editing the same .psd file simultaneously.
- Fossil is not a serious contender for large binary repos. It's great for what it's designed for (small-to-medium projects with integrated project management), but it chokes on the scale that game dev demands.
`─────────────────────────────────────────────────`

---

## 4. Merge Strategies & Living with Conflicts

### Git
Uses the "ort" (Ostensibly Recursive's Twin) three-way merge strategy by default. Excellent at detecting renames, handling whitespace differences, and merging non-overlapping changes. When conflicts occur, they're marked inline and you resolve them with your editor or a merge tool. Git provides `rerere` (reuse recorded resolution) to remember how you resolved a conflict and auto-apply it next time.

**In practice:** if your team uses short-lived branches and merges frequently, conflicts are small and manageable. If branches live for weeks or months, merges become painful. Rebasing keeps history linear but can cause repeated conflict resolution if the base has diverged significantly.

### Fossil
Also uses three-way merge, always creates merge commits (no fast-forward). Conflict resolution is similar to Git but users report it feels "painless" because Fossil's autosync keeps branches closer to the trunk, reducing divergence. Since history rewriting is not allowed, you never deal with rebase conflicts.

One Fossil user's take: "I've made some silly mistakes with Fossil and I'm doing my first large merge right now, but the learning curve has been much flatter."

### SVN
Three-way merge with `svn:mergeinfo` tracking since 1.5. SVN 1.8 added client-side rename tracking, SVN 1.11 improved tree conflict resolution. Conflicts must be resolved before committing — you can't push a conflicted state to the server. This means the central repo is always in a clean state.

**In practice:** SVN merges used to be notoriously bad (pre-1.5). Modern SVN with merge tracking is reasonable for text files. For binary files, you don't merge — you lock. The "merge is impossible, so prevent the problem" philosophy is honest and practical.

`★ Insight ─────────────────────────────────────`
- The real merge question isn't "which algorithm is best?" — they all use three-way merge and they're all fine for text. The question is "how do you handle the stuff that **can't** be merged?" Git says "good luck." SVN says "lock it." Fossil says "it's not our target use case."
- Jonathan Blow's approach with The Witness was clever: store game entities as individual text files (not a binary database) so SVN could merge them. Allocated entity ID ranges to developers to reduce natural conflicts. Binary assets got locked. This is designing your project structure *around* your VCS's strengths.
`─────────────────────────────────────────────────`

---

## 5. Repository Sizes

### Git
Repos grow with history. `git gc` repacks objects and can dramatically reduce size (one example: 2.1 GB → 850 MB). Partial clones (`--filter=blob:none`) and shallow clones (`--depth=1`) reduce what you download, but limit what you can do offline. Large monorepos (Linux kernel, LLVM) work but require tuning and maintenance.

### Fossil
Single SQLite database grows linearly with content. Works well up to a few GB. The manifest format (lists all files per check-in) creates scaling issues with hundreds of thousands of files. Not suitable for very large codebases. The SQLite project itself uses Fossil — that's the sweet spot.

### SVN
Server repos can grow very large (100+ GB in enterprise). Performance depends on server config. Sparse checkout means devs don't need the whole thing locally. Repository sharding is sometimes used for very large deployments.

---

## 6. Self-Hosting

### Git
Git itself has no web interface, no access control, no user management. You need additional software:
- **Minimal:** bare repo + SSH (no web UI, no issues, no PRs)
- **Lightweight:** Gitea, cgit, or Soft Serve
- **Full-featured:** GitLab (heavy — wants its own server with 4+ GB RAM, PostgreSQL, Redis)

Setting up a proper self-hosted Git forge is a multi-hour project. Maintaining it is ongoing work.

### Fossil
**This is Fossil's superpower.** The entire system — VCS, web UI, wiki, tickets, forums, user management, RBAC — is a single static binary. Self-hosting options:
- Drop a CGI script on any web host ($3/month shared hosting works)
- Run `fossil server` as a standalone HTTP server
- Deploy via SCGI behind nginx
- Run on a Raspberry Pi

Standing up a complete project management + VCS system takes minutes, not hours. The SQLite database is a single file — backup means copying one file.

### SVN
Moderate complexity. Two common approaches:
- **svnserve:** Simple daemon, custom protocol. Easy to set up, limited features.
- **Apache + mod_dav_svn:** Full HTTP/HTTPS access, integrates with Apache auth. More setup but more capable.

No built-in web UI for browsing, issues, or wiki — you'd add ViewVC or similar.

`★ Insight ─────────────────────────────────────`
- Fossil's self-hosting story is genuinely remarkable. If you value owning your infrastructure and not depending on GitHub/GitLab, Fossil is the only system where "self-hosting" doesn't mean "becoming a sysadmin."
- Git's self-hosting complexity is why GitHub has 100M+ users. The tool itself is incomplete without a forge layer, which creates platform dependency — ironic for a system designed for distributed, decentralized development.
`─────────────────────────────────────────────────`

---

## 7. Robustness & Maintenance

### Git
SHA-1 (transitioning to SHA-256) content addressing provides strong integrity guarantees. `git fsck` detects corruption but recovery is manual. Distributed clones serve as natural backups. Requires periodic `git gc` for performance. History rewriting (`rebase`, `filter-branch`, `push --force`) can permanently destroy work if misused.

### Fossil
**Best-in-class data integrity.** Multiple layers of defense:
1. SQLite ACID transactions — atomic commits with rollback on failure
2. Delta verification before commit — recomputes hashes of all modified files
3. Checksums on all artifacts and deltas
4. Checksums over all files in each check-in, verified after checkout
5. History is immutable — no rewriting, no force-push, no squash

From the Fossil docs: "Fossil takes the philosophy of the tortoise: reliability is more important than raw speed." Over 13+ years of self-hosting, they report zero data loss. This level of defensive programming is unusual in any software, let alone a VCS.

### SVN
MD5 checksums, reasonable corruption detection. Single central server is a single point of failure — regular backups essential. `svnadmin verify` checks repository integrity. Mature and battle-tested but less defensive than Fossil.

`★ Insight ─────────────────────────────────────`
- Fossil's "verify everything before committing" approach costs milliseconds per commit and prevents entire classes of data loss. The fact that Git doesn't do this (and relies on after-the-fact `fsck`) is a design choice that prioritizes speed over safety.
- Git's mutability (rebase, force-push, filter-branch) is philosophically at odds with "version control" — the thing that's supposed to be the immutable record. Fossil's stance is that if you committed it, it happened, and pretending otherwise is dishonest.
`─────────────────────────────────────────────────`

---

## 8. Ease of Use

### SVN
Lowest learning curve. `svn checkout`, `svn update`, `svn commit` — done. No staging area, no local/remote distinction, no rebasing. The centralized model is conceptually simple: there's one repo, you get files from it, you put files back. Works well for teams where not everyone is a VCS power user (artists, designers, writers).

### Fossil
Gentler than Git, steeper than SVN. Commands are consistent and well-documented. Key UX wins:
- `fossil undo` reverses recent operations without losing data (vs Git's `reset --hard` which destroys work)
- Merges require a separate commit step, so you can test before finalizing
- No staging area — `fossil commit` commits everything (like SVN)
- Built-in web UI means you're never far from a visual overview

One user: "Compared to git, fossil feels straightforward and easy to use. Doesn't get in my way."

### Git
Steep learning curve. Concepts like staging area, local vs remote branches, rebasing, detached HEAD, reflog, and the plumbing/porcelain distinction are powerful but overwhelming. The command interface is notoriously inconsistent (`git checkout` doing five different things until `switch`/`restore` were added). However, mastery pays off with unmatched flexibility.

**The real UX issue:** Git presents "all skills unlocked" from day one. There's no progressive disclosure. A junior dev sees the same interface as a kernel maintainer.

---

## 9. My Take

**For a project like Jonathan Blow's (game dev, significant binary assets, small-to-medium team):** SVN is the right call. Native binary delta compression, enforced file locking, sparse checkout, and conceptual simplicity. The lack of distributed capabilities is irrelevant when your team is in one location or on one VPN.

**For a project like SQLite or a personal multi-project setup where you want VCS + tickets + wiki in one place:** Fossil. The self-hosting story, data integrity guarantees, and integrated project management are unmatched. Just don't throw 50 GB of textures at it.

**For open-source code, distributed teams, or anything that needs to integrate with the modern dev ecosystem (CI/CD, PRs, code review):** Git. The ecosystem is the moat. GitHub/GitLab's network effects outweigh Git's UX warts and binary-file weaknesses.

**For large binary assets with a distributed team:** Git + LFS is the least-bad option. LFS solves the clone-time problem but doesn't solve the "two people edited the same .blend file" problem (LFS locking is opt-in and unenforced). If you can afford it, Perforce is what AAA studios actually use — it's the only system that does distributed + large binaries + enforced locking well. But it costs money and is proprietary.

`★ Insight ─────────────────────────────────────`
- The elephant in the room: **no open-source VCS does large binaries + distributed + locking well.** Git-LFS is a workaround, not a solution. SVN does binaries + locking but isn't distributed. Fossil does distributed + integrity but not large binaries. Perforce does everything but isn't open-source. This is a genuinely unsolved problem in open-source tooling.
- Jonathan Blow's choice of SVN isn't retrograde — it's pragmatic. He evaluated the trade-offs and picked the tool that prevented the most damaging class of problems (binary merge conflicts) at the cost of a capability he didn't need (distributed offline commits). That's good engineering.
`─────────────────────────────────────────────────`

## References

- [Blender Studio VCS benchmarks (2024)](https://studio.blender.org/blog/version-control-benchmarks/)
- [Fossil vs Git (official comparison)](https://fossil-scm.org/home/doc/tip/www/fossil-v-git.wiki)
- [Fossil self-check documentation](https://fossil-scm.org/home/doc/tip/www/selfcheck.wiki)
- [Fossil branching model](https://fossil-scm.org/home/doc/tip/www/branching.wiki)
- [SVN merge tracking (Red Bean book)](https://svnbook.red-bean.com/en/1.7/svn.branchmerge.basicmerging.html)
- [Jonathan Blow on The Witness entity system & SVN](https://www.youtube.com/watch?v=4RlvRqByzQM) (GDC talk)
- [Git LFS documentation](https://git-lfs.com/)
- [Fossil server deployment](https://fossil-scm.org/home/doc/tip/www/server/)
- [Fossil ticket system](https://fossil-scm.org/home/doc/tip/www/tickets.wiki)
