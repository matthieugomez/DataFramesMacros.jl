module PairsMacros

include("utils.jl")

macro cols(arg)
    esc(rewrite(arg, false))
end

macro rows(arg)
    esc(rewrite(arg, true))
end

const SUBSTITUTE = :$
const LEAVEALONE = :^

function rewrite(e, byrow)
    if isa(e, Expr) && (e.head === :(=))
        # e.g. y = mean(x)
        lhs = e.args[1]
        if lhs isa Symbol
            target = QuoteNode(lhs)
        elseif lhs.head === SUBSTITUTE
            length(lhs.args) == 1 || throw("Malformed Expression")
            target = lhs.args[1]
        else
            throw("Malformed Expression")
        end
        source, fn, has_fn = rewrite_rhs(e.args[2], byrow)
        if has_fn
            return quote Base.:(=>)($source, Base.:(=>)($fn, $target)) end
        else
            return quote Base.:(=>)($source, $target) end
        end
    else
        # e.g. mean(x)
        source, fn, has_fn = rewrite_rhs(e, byrow)
        if has_fn
            return quote Base.:(=>)($source, $fn) end
        else
            return source
        end
    end
end

function rewrite_rhs(rhs, byrow)
    # parse the rhs hand side
    membernames = Dict{Any, Symbol}()
    rhs = parse_columns!(membernames, rhs)
    source = Expr(:vect, keys(membernames)...)
    if length(keys(membernames)) == 1
        source = first(keys(membernames))
    end
    fn = quote $(Expr(:tuple, values(membernames)...)) -> $rhs end
    set = Set(values(membernames))
    if isatomic(rhs, set)
        # e.g. mean(skipmissing(x)) becomes skipmissing ∘ mean
        # this avoids anonymous function to avoid compilation
        fn = make_composition(rhs, set)
    end
    if byrow
        fn = quote DataFrames.ByRow($fn) end
    end
    return source, fn, rhs ∉ set
end

parse_columns!(membernames::Dict, x) = x
function parse_columns!(membernames::Dict, q::Symbol)
    addkey!(membernames, QuoteNode(q))
end
function parse_columns!(membernames::Dict, e::Expr)
    if e.head === SUBSTITUTE
        length(e.args) == 1 || throw("Malformed Expression")
        addkey!(membernames, e.args[1])
    elseif (e.head === :call) && (e.args[1] == LEAVEALONE)
        length(e.args) == 2 || throw("Malformed Expression")
        e.args[2]
    elseif e.head === :.
        length(e.args) == 2 || throw("Malformed Expression")
        Expr(:., e.args[1], parse_columns!(membernames, e.args[2]))
    elseif (e.head === :call) && length(e.args) > 1
        Expr(e.head, e.args[1], (parse_columns!(membernames, x) for x in e.args[2:end])...)
    elseif (e.head === :call) && length(e.args) == 1
        e
    else
        Expr(e.head, (parse_columns!(membernames, x) for x in e.args)...)
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