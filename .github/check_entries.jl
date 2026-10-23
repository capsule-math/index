# Validate index entries. Called by .github/workflows/check.yml with the paths
# of the entries a pull request adds or changes. Reads them as data only.
using JSON, Downloads

const LOCATION = r"^(https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/tree/([0-9a-f]{40})((?:/[A-Za-z0-9_.-]+)*)|https://doi\.org/10\.[0-9]+/\S+)$"
const FIELDS   = Set(["title", "authors", "run", "paper", "keywords", "produce", "location"])

function resolves(url)
    for method in ("HEAD", "GET")          # some hosts refuse HEAD
        try
            r = Downloads.request(url; method, output = devnull, throw = false)
            r isa Downloads.Response && 200 <= r.status < 400 && return true
        catch
        end
    end
    return false
end

function check(path)
    errs = String[]
    occursin(r"^entries/[a-z0-9]+(-[a-z0-9]+)*\.json$", path) ||
        push!(errs, "file name must be entries/<lowercase-hyphenated>.json")
    e = try JSON.parsefile(path) catch err; return ["not valid JSON: $(sprint(showerror, err))"] end
    e isa AbstractDict || return ["not a JSON object"]
    for k in ("title", "run", "location")
        get(e, k, "") isa AbstractString && !isempty(strip(get(e, k, ""))) || push!(errs, "missing or empty: $k")
    end
    a = get(e, "authors", nothing)
    a isa AbstractVector && !isempty(a) && all(x -> x isa AbstractString && !isempty(x), a) || push!(errs, "authors must be a non-empty list of names")
    for k in keys(e)
        k in FIELDS || push!(errs, "unknown field: $k")
    end
    haskey(e, "keywords") && !(e["keywords"] isa AbstractVector) && push!(errs, "keywords must be a list")
    loc = get(e, "location", "")
    m = loc isa AbstractString ? match(LOCATION, loc) : nothing
    if m === nothing
        push!(errs, "location must be https://github.com/<owner>/<repo>/tree/<40-hex commit>[/<folder>] or https://doi.org/<doi>")
    elseif !resolves(loc)
        push!(errs, "location does not resolve: $loc")
    elseif m.captures[2] !== nothing
        # GitHub: the package at that commit must have an entry.json agreeing with this one
        base = "https://raw.githubusercontent.com/$(m.captures[2])/$(m.captures[3])/$(m.captures[4])$(something(m.captures[5], ""))"
        raw = "$base/entry.json"
        pkg = try JSON.parse(String(take!(Downloads.download(raw, IOBuffer())))) catch; nothing end
        if pkg === nothing
            push!(errs, "no readable entry.json at that commit")
        else
            for k in ("title", "authors", "run")
                get(pkg, k, nothing) == get(e, k, nothing) || push!(errs, "$k differs from the package's entry.json")
            end
            for f in ("statement.md",)
                resolves("$base/$f") || push!(errs, "$f not found at that location")
            end
        end
    end
    return errs
end

paths = filter(!isempty, split(get(ENV, "ENTRIES", ""), '\n'))
isempty(paths) && (println("no entries changed"); exit(0))
bad = false
for p in paths
    errs = isfile(p) ? check(p) : String[]      # deleted files are fine
    if isempty(errs)
        println("pass ", p)
    else
        bad = true
        println("fail ", p)
        foreach(x -> println("     ", x), errs)
    end
end
exit(bad ? 1 : 0)
