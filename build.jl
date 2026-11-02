#!/usr/bin/env julia
# Render entries/*.json into index.html, and one page per keyword in tags/.
# Run from this directory:  julia --project=. build.jl
import Pkg; Pkg.instantiate()
using JSON, Dates, TOML, Downloads

esc(s) = replace(string(s), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;")

# Turn "doi:10.xxxx/yyy" and "arXiv:xxxx.xxxxx" (or old-style ids) into links.
# Runs on already-escaped text; the identifiers themselves contain no & < > ".
function linkify(t)
    t = replace(t, r"(?i)\bdoi:\s*(10\.\d{4,9}/[^\s;,]*[^\s;,.)])" =>
                   s"<a href=\"https://doi.org/\1\">doi:\1</a>")
    t = replace(t, r"(?i)\barxiv:\s*((?:[a-z-]+(?:\.[a-z]{2})?/\d{7}|\d{4}\.\d{4,5})(?:v\d+)?)" =>
                   s"<a href=\"https://arxiv.org/abs/\1\">arXiv:\1</a>")
    return t
end

function where(loc)
    startswith(loc, "https://doi.org/10.5281/zenodo.") && return "Zenodo"
    startswith(loc, "https://doi.org/")                && return "DOI"
    startswith(loc, "https://github.com/")             && return "GitHub"
    return "link"
end

# ---- keywords ----------------------------------------------------------------
# keywords.toml: one [heading] per group; canonical keyword = [synonyms...].
# Matching ignores case, dash style, repeated spaces and a trailing "s".

function normkey(s)
    t = lowercase(strip(s))
    t = replace(t, r"[‐‑‒–—]" => "-")
    t = replace(t, r"\s+" => " ")
    return endswith(t, "s") ? chop(t) : t
end

slug(s) = strip(replace(lowercase(s), r"[^a-z0-9]+" => "-"), '-')

function load_vocabulary(path)
    isfile(path) || return Pair{String,Vector{String}}[], Dict{String,String}()
    data   = TOML.parsefile(path)
    order  = [m[1] for m in eachmatch(r"^\s*\[([^\]]+)\]"m, read(path, String))]
    lookup = Dict{String,String}()
    groups = Pair{String,Vector{String}}[]
    for heading in order
        terms = collect(keys(data[heading]))
        for t in terms, s in [t; data[heading][t]]
            lookup[normkey(s)] = t
        end
        push!(groups, heading => sort(terms, by = lowercase))
    end
    return groups, lookup
end

canonical(k, lookup) = get(lookup, normkey(k),
    String(replace(replace(strip(k), r"[‐‑‒–—]" => "-"), r"\s+" => " ")))
entry_tags(e, lookup) = unique(canonical(k, lookup) for k in get(e, "keywords", String[]))
taglink(k; prefix = "tags/") = """<a href="$(prefix)$(slug(k)).html">$(esc(k))</a>"""

const STYLE = """<style>
  html{background:#fff;color:#000}
  body{font:14px/1.45 ui-monospace,Menlo,Consolas,"Liberation Mono",monospace;max-width:76rem;margin:3rem auto;padding:0 1.5rem}
  h1{font-size:1rem;font-weight:700;letter-spacing:.08em;text-transform:uppercase;margin:0 0 .5rem}
  p{margin:0 0 2rem;max-width:48rem}
  a{color:#000}
  table{border-collapse:collapse;width:100%;border-top:2px solid #000}
  th{font-weight:700;letter-spacing:.06em;text-transform:uppercase;font-size:.75rem;border-bottom:1px solid #000}
  td,th{padding:.6rem .8rem .6rem 0;vertical-align:top;text-align:left}
  td{border-bottom:1px solid #000}
  .muted,.muted a{color:#666}
  .tags{margin:0 0 2rem;font-size:.85rem}
  .tags div{margin:.15rem 0}
  footer{margin-top:2rem;font-size:.75rem;color:#666}
</style>"""

page(title, body) = """<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$(esc(title))</title>
$STYLE
$body
<footer>generated $(Dates.format(today(), "yyyy-mm-dd"))</footer>
"""

# ---- check status (GitHub Actions) -------------------------------------------
# For a package hosted on GitHub whose repository calls the reusable workflow
# .github/workflows/check-proofs.yml of this repository (see README): the
# result of the job "<folder> (pinned)" of the latest completed run on the
# default branch, linked, and, when that run is not green, the latest run in
# which the job was green. Needs the network; GITHUB_TOKEN (set by pages.yml)
# raises the API rate limit. Anything that fails degrades to "n/a".

const API = "https://api.github.com"

function api(path)
    headers = ["Accept" => "application/vnd.github+json", "User-Agent" => "capsule-math-index"]
    haskey(ENV, "GITHUB_TOKEN") && push!(headers, "Authorization" => "Bearer " * ENV["GITHUB_TOKEN"])
    io = IOBuffer()
    r = Downloads.request(API * path; output = io, headers, throw = false)
    r isa Downloads.Response && r.status == 200 || return nothing
    return JSON.parse(String(take!(io)))
end

# location → (owner, repo, folder), folder "." for a package at the root
function github_package(loc)
    m = match(r"^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/tree/[0-9a-f]{40}((?:/[A-Za-z0-9_.-]+)*)$", loc)
    m === nothing && return nothing
    return (m[1], m[2], isempty(m[3]) ? "." : m[3][2:end])
end

shortdate(t) = Dates.format(DateTime(t[1:19]), "yyyy-mm-dd")

# conclusion of the job "<name> (pinned)" of a run; through the reusable workflow
# the job is named "<caller job> / <name> (pinned)", hence the suffix match
function package_job(owner, repo, run, name)
    jobs = api("/repos/$owner/$repo/actions/runs/$(run["id"])/jobs?per_page=100")
    jobs === nothing && return nothing
    for j in jobs["jobs"]
        (j["name"] == "$name (pinned)" || endswith(j["name"], "/ $name (pinned)")) && return j["conclusion"]
    end
    return nothing
end

function check_status(loc)
    pkg = github_package(loc)
    pkg === nothing && return """<span class="muted">—</span>"""
    owner, repo, name = pkg
    runs = api("/repos/$owner/$repo/actions/runs?event=push&status=completed&per_page=$(haskey(ENV, "GITHUB_TOKEN") ? 30 : 8)")
    runs === nothing && return """<span class="muted">n/a</span>"""
    runs = [r for r in runs["workflow_runs"] if r["name"] == "Check proofs"]
    latest = nothing
    for r in runs
        c = package_job(owner, repo, r, name)
        c in ("success", "failure") || continue        # no verdict on this package (cancelled, skipped, absent)
        link(mark) = """<a href="$(esc(r["html_url"]))">$(mark)$(r["head_sha"][1:7]) $(shortdate(r["updated_at"]))</a>"""
        if latest === nothing
            latest = (c == "success", link(c == "success" ? "✓ " : "✗ "))
            latest[1] && return latest[2]
        elseif c == "success"
            return latest[2] * """<br><span class="muted">last green: $(link(""))</span>"""
        end
    end
    latest === nothing && return """<span class="muted">no run</span>"""
    return latest[2] * """<br><span class="muted">no green run found</span>"""
end

# ---- entries -------------------------------------------------------------------

groups, lookup = load_vocabulary("keywords.toml")

entries = [JSON.parsefile(p) for p in sort(filter(f -> endswith(f, ".json"),
           isdir("entries") ? readdir("entries"; join = true) : String[]))]

const STATUS = Dict{String,String}()   # location => rendered check status (one query per package)

function row(e, prefix)
    loc  = e["location"]
    tags = entry_tags(e, lookup)
    kw   = isempty(tags) ? "" : """<br><span class="muted">$(join(taglink.(tags; prefix), ", "))</span>"""
    """<tr>
  <td>$(esc(e["title"]))<br><span class="muted">$(esc(join(e["authors"], ", ")))</span>$kw</td>
  <td>$(linkify(esc(get(e, "paper", ""))))</td>
  <td><a href="$(esc(loc))">$(where(loc))</a></td>
  <td>$(get!(() -> check_status(loc), STATUS, loc))</td>
</tr>"""
end

table(es, prefix) = """<table>
<tr><th>Theorem</th><th>Paper</th><th>Location</th><th>Check</th></tr>
$(join((row(e, prefix) for e in es), "\n"))
</table>"""

# keyword => entries, for keywords in use
bytag = Dict{String,Vector{Any}}()
for e in entries, k in entry_tags(e, lookup)
    push!(get!(bytag, k, Any[]), e)
end

# keyword overview: grouped by heading, used keywords only, with counts
function overview()
    lines = String[]
    listed = Set{String}()
    for (heading, terms) in groups
        used = [t for t in terms if haskey(bytag, t)]
        union!(listed, used)
        isempty(used) && continue
        push!(lines, "<div>$(esc(heading)): " *
              join(("$(taglink(t)) ($(length(bytag[t])))" for t in used), ", ") * "</div>")
    end
    other = sort([k for k in keys(bytag) if !(k in listed)], by = lowercase)
    isempty(other) || push!(lines, "<div>other: " *
        join(("$(taglink(t)) ($(length(bytag[t])))" for t in other), ", ") * "</div>")
    return isempty(lines) ? "" : """<div class="tags">$(join(lines, "\n"))</div>"""
end

# ---- write ----------------------------------------------------------------------

n = length(entries)
write("index.html", page("Proof packages", """
<h1>Proof packages</h1>
<p>Computer-assisted proofs packaged as statement + inputs + checker. Format: <a href="https://github.com/capsule-math/spec">spec</a>.<br><span class="muted">$n $(n == 1 ? "entry" : "entries")</span></p>
$(overview())
$(table(entries, "tags/"))
"""))

rm("tags"; force = true, recursive = true)       # no stale pages
mkpath("tags")
for (k, es) in bytag
    sort!(es, by = e -> lowercase(e["title"]))
    write(joinpath("tags", slug(k) * ".html"), page("$(k) · Proof packages", """
<h1><a href="../index.html">Proof packages</a> / $(esc(k))</h1>
<p>$(length(es)) $(length(es) == 1 ? "entry" : "entries").</p>
$(table(es, ""))
"""))
end

println(n, " entries, ", length(bytag), " keyword pages")
