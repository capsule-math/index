# Index

A list of computer-assisted proofs packaged following
[capsule-math/spec](https://github.com/capsule-math/spec). One file per package
in `entries/`: the package's `entry.json` plus its `location`, a GitHub URL at a
commit or a DOI. The [site](https://capsule-math.github.io/index/) is rebuilt
from these files on every push to `main`.

## Listing a package

Open a pull request adding `entries/<package-name>.json`: the package's
`entry.json` with `location` added.

- `<package-name>`: named after the theorem, lowercase-hyphenated.
- `location`: `https://github.com/<owner>/<repo>/tree/<40-character commit>`,
  plus `/<folder>` if the package is a folder of a larger repository, or
  `https://doi.org/<doi>`. Tags are not accepted.
- `keywords` (optional): prefer those in [`keywords.toml`](keywords.toml);
  anything else is listed under "other".
- Several packages in one repository: one entry each; one pull request may add
  them all.

A check runs on the pull request: valid entry, location resolves, and for a
GitHub location, the package's own `entry.json` agrees with the entry.

## Packaging a proof with an AI assistant

With an assistant that can run commands and use git (Claude Code, or similar),
this prompt takes existing proof code all the way to a pull request:

```
Read the specification at https://github.com/capsule-math/spec (README.md and
entry.schema.json) and the template at https://github.com/capsule-math/template,
Turn my proof code into a package following that spec, in a new repository
created from the template:

1. Separate what the checker verifies from how its inputs are obtained.
   Freeze inputs that are costly to produce (write them to `data/`, record
   them with `tools/hash_data.jl`); put the code that produces the others
   behind a `produce` command. Keep the checker's arithmetic identical to my
   original verification.
2. Make the checker print each condition as pass/fail with its enclosure and
   exit 0 iff all pass. Run it and show me the output.
3. Draft `statement.md` and `entry.json`. Ask me what you cannot determine
   from the code: which lemma each condition corresponds to, what the inputs
   mean, the paper reference.
4. When I confirm, push the package (or tell me how to archive it on Zenodo if
   I prefer), then open a pull request to
   https://github.com/capsule-math/index adding `entries/<package-name>.json`
   (named after the theorem, lowercase-hyphenated) with `location` set to the
   commit or DOI.

If you cannot run commands, produce the files and tell me the remaining steps.
```
