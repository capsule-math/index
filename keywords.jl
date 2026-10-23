# keywords.jl: keyword vocabulary, synonyms, tag pages
using TOML

h(s) = replace(string(s), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;")

# case-, dash- and plural-insensitive key
function normkey(s)
    t = lowercase(strip(s))
    t = replace(t, r"[‐‑‒–—]" => "-")
    t = replace(t, r"\s+" => " ")
    return endswith(t, "s") ? chop(t) : t
end

slug(s) = strip(replace(lowercase(s), r"[^a-z0-9]+" => "-"), '-')

# returns heading => canonical terms (file order), and normalized word => canonical
function load_vocabulary(path = "keywords.toml")
    data  = TOML.parsefile(path)
    order = [m[1] for m in eachmatch(r"^\[([^\]]+)\]"m, read(path, String))]
    lookup = Dict{String,String}()
    groups = Pair{String,Vector{String}}[]
    for heading in order
        terms = sort(collect(keys(data[heading])), by = lowercase)
        for t in terms, s in [t; data[heading][t]]
            lookup[normkey(s)] = t
        end
        push!(groups, heading => terms)
    end
    return groups, lookup
end

canonical(k, lookup) = get(lookup, normkey(k), strip(k))
entry_tags(e, lookup) = unique(canonical(k, lookup) for k in get(e, "keywords", String[]))
taglink(k; prefix = "tags/") = "$(h(k))"

# one page per keyword in use; returns keyword => entries
function write_tag_pages(entries, lookup; outdir = "site")
    bytag = Dict{String,Vector{Any}}()
    for e in entries, k in entry_tags(e, lookup)
        push!(get!(bytag, k, Any[]), e)
    end
    mkpath(joinpath(outdir, "tags"))
    for (k, es) in bytag
        items = join((" $(h(e["title"])) "
                      for e in sort(es, by = e -> lowercase(e["title"]))), "\n")
        write(joinpath(outdir, "tags", slug(k) * ".html"), """
        <!doctype html><meta charset="utf-8">
        <link rel="stylesheet" href="../style.css">
        index
        $(h(k))
        
        $items
        
        """)
    end
    return bytag
end

# keyword overview for the top of index.html, used keywords only
function tag_index_html(groups, bytag)
    lines = String[]
    for (heading, terms) in groups
        used = [t for t in terms if haskey(bytag, t)]
        isempty(used) && continue
        push!(lines, " $(h(heading)): " *
              join(("$(taglink(t)) ($(length(bytag[t])))" for t in used), ", ") * " ")
    end
    other = sort([k for k in keys(bytag) if !any(k in ts for (_, ts) in groups)], by = lowercase)
    isempty(other) || push!(lines, " other: " * join(taglink.(other), ", ") * " ")
    return join(lines, "\n")
end
