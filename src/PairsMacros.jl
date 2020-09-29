module PairsMacros
include("utils.jl")

"""
Create Pairs expressions for use in `DataFrames.jl`

### Details
All symbols are assumed to refer to columns in the DataFrames, with the exception of:
- `missing`
- first `args` of a `:call` or `:.` expression (function calls)
- arguments inside of a splicing/interpolation expression `\$()` (refer to column names programatically).
- arguments inside  `^()` (refer to outside variables)

See also `@rows`

### Examples
```julia
julia> using PairsMacros
julia> @cols z = sum(x)
[:x] => sum => :z
julia> u = :y
julia> @cols z = sum(\$u)
[:y] => sum => :z
julia> @cols \$u = sum(x)
[:x] => sum => :y
julia> @cols z = sum(\$"my variable name")
"my variable name" => sum => :z
julia> @cols z = map(^(cos), y)
[:y] => (x -> map(cos, x)) => :z
```
"""
macro cols(arg)
    esc(rewrite(arg, false))
end

"""
Create Pairs expressions for use in `DataFrames.jl`, where the function is enclosed by `ByRow`

### Details
All symbols are assumed to refer to columns in the DataFrames, with the exception of:
- `missing`
- first `args` of a `:call` or `:.` expression (function calls)
- arguments inside of a splicing/interpolation expression `\$()` (refer to column names programatically).
- arguments inside  `^()` (refer to outside variables)

See also `@cols`

### Examples
```julia
using PairsMacros
julia> @rows z = abs(x)
[:x] => ByRow(abs) => :z
julia> @rows z = tryparse(^(Float64), x)
[:x] => (x -> tryparse(Float64, x) => :z
```
"""
macro rows(arg)
    esc(rewrite(arg, true))
end

# multiple argument version
macro cols(args...)
    Expr(:..., Expr(:tuple, (esc(rewrite(x, false)) for x in args)...))
end
macro rows(args...)
    Expr(:..., Expr(:tuple, (esc(rewrite(x, true)) for x in args)...))
end

function rewrite(e, byrow)
    if isa(e, Expr) && (e.head === :(=))
        # e.g. y = mean(x)
        lhs = e.args[1]
        if lhs isa Symbol
            target = QuoteNode(lhs)
        elseif lhs.head === :$
            target = lhs.args[1]
        end
        source, fn, has_fn = rewrite_rhs(e.args[2], byrow)
        if has_fn
            out = quote $source => $fn => $target end
        else
            out = quote $source => $target end
        end
    else
        # e.g. mean(x)
        source, fn, has_fn = rewrite_rhs(e, byrow)
        if has_fn
            out = quote $source => $fn end
        else
            out = source
        end
    end
    return out
end

function rewrite_rhs(rhs, byrow)
    membernames = Dict{Any, Symbol}()
    body = parse_columns!(membernames, rhs)
    k, v = keys(membernames), values(membernames)
    if length(k) == 1
        source = first(k)
    else
        source = Expr(:vect, k...)
    end
    if is_circ(body, v)
        # e.g. mean(skipmissing(x))
        # in this case, use mean ∘ skipmissing
        # this avoids precompilation + allows fast path
        fn = make_circ(body, v)
    else
        # in this case, use anonymous function
        fn = quote $(Expr(:tuple, v...)) -> $body end
    end
    if byrow
        fn = quote DataFrames.ByRow($fn) end
    end
    return source, fn, body ∉ v
end

parse_columns!(membernames::Dict, x) = x
function parse_columns!(membernames::Dict, x::Symbol)
    if x === :missing
        x
    else
        addkey!(membernames, QuoteNode(x))
    end
end
function parse_columns!(membernames::Dict, e::Expr)
    if e.head === :$
        # e.g. $(x)
        addkey!(membernames, e.args[1])
    elseif (e.head === :call) && (e.args[1] == :^) && (length(e.args) == 2)
        # e.g. ^(x)
        e.args[2]
    elseif ((e.head === :.) & (e.args[1] isa Symbol)) | ((e.head === :call) & (e.args[1] isa Symbol))
        # e.g. f(x) or f.(x)
        Expr(e.head, e.args[1], 
            (parse_columns!(membernames, x) for x in Iterators.drop(e.args, 1))...)
    else
        Expr(e.head, 
            (parse_columns!(membernames, x) for x in e.args)...)
    end
end

function addkey!(membernames::Dict, nam)
    if !haskey(membernames, nam)
        membernames[nam] = gensym()
    end
    membernames[nam]
end

# when Cols() implemented in DataFrames.jl, 
# @cols(f, r".*") could be used to return Cols(r".*") .=> f
export @rows, @cols

end