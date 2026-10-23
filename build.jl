#!/usr/bin/env julia
# Render entries/*.json into index.html.
# Run from this directory:  julia --project=. build.jl
import Pkg; Pkg.instantiate()
using JSON, Dates

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

rows = String[]
for p in sort(filter(f -> endswith(f, ".json"), isdir("entries") ? readdir("entries"; join = true) : String[]))
    e = JSON.parsefile(p)
    loc = e["location"]
    push!(rows, """<tr>
  <td>$(esc(e["title"]))<br><span class="muted">$(esc(join(e["authors"], ", ")))</span></td>
  <td>$(linkify(esc(get(e, "paper", ""))))</td>
  <td><a href="$(esc(loc))">$(where(loc))</a></td>
</tr>""")
end

page = """<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Proof packages</title>
<style>
  html{background:#fff;color:#000}
  body{font:14px/1.45 ui-monospace,Menlo,Consolas,"Liberation Mono",monospace;max-width:76rem;margin:3rem auto;padding:0 1.5rem}
  h1{font-size:1rem;font-weight:700;letter-spacing:.08em;text-transform:uppercase;margin:0 0 .5rem}
  p{margin:0 0 2rem;max-width:48rem}
  a{color:#000}
  table{border-collapse:collapse;width:100%;border-top:2px solid #000}
  th{font-weight:700;letter-spacing:.06em;text-transform:uppercase;font-size:.75rem;border-bottom:1px solid #000}
  td,th{padding:.6rem .8rem .6rem 0;vertical-align:top;text-align:left}
  td{border-bottom:1px solid #000}
  .muted{color:#666}
  footer{margin-top:2rem;font-size:.75rem;color:#666}
</style>
<h1>Proof packages</h1>
<p>Computer-assisted proofs packaged as statement + inputs + checker. Format: <a href="https://github.com/capsule-math/spec">spec</a>.</p>
<table>
<tr><th>Theorem</th><th>Paper</th><th>Location</th></tr>
$(join(rows))
</table>
<footer>$(length(rows)) $(length(rows) == 1 ? "entry" : "entries") · generated $(Dates.format(today(), "yyyy-mm-dd"))</footer>
"""
write("index.html", page)
println(length(rows), " entries")

include("keywords.jl")
groups, lookup = load_vocabulary("keywords.toml")
bytag = write_tag_pages(entries, lookup; outdir = "site")
# above the table:    tag_index_html(groups, bytag)
# in each table row:  join(taglink.(entry_tags(e, lookup)), ", ")
