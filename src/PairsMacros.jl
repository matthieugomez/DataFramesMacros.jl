module PairsMacros
using DataFrames

include("utils.jl")

macro cols(arg)
    esc(make_vec_to_fun(arg, false))
end

macro rows(arg)
    esc(make_vec_to_fun(arg, true))
end

function make_vec_to_fun(e, byrow)
    if isa(e, Expr) && (e.head === :(=))
        # e.g. y = mean(x)
        lhs = e.args[1]
        if lhs isa Symbol
            target = QuoteNode(lhs)
        elseif lhs.head === :$
            length(lhs.args) == 1 || throw("Malformed Expression")
            target = lhs.args[1]
        else
            throw("Malformed Expression")
        end
        source, f, has_fun = parse_helper(e.args[2], byrow)
        if has_fun
            return quote Base.:(=>)($source, Base.:(=>)($f, $target)) end
        else
        	return quote Base.:(=>)($source, $target) end
        end
    else
        # e.g. mean(x)
        source, f, has_fun = parse_helper(e, byrow)
        if has_fun
            return quote Base.:(=>)($source, $f) end
        else
        	return source
        end
    end
end

function parse_helper(rhs, byrow)
    # parse the rhs hand side
    membernames = Dict{Any, Symbol}()
    rhs = parse_columns!(membernames, rhs)
    source = Expr(:vect, keys(membernames)...)
    if length(keys(membernames)) == 1
        source = first(keys(membernames))
    end
    set = Set(values(membernames))
    if isatomic(rhs, set)
        # e.g. mean(skipmissing(x)) becomes skipmissing ∘ mean
        # this avoids anonymous function to avoid compilation
        # Would be nice to also handle x + x but hard (i) order matters (x-y) (ii) duplication matters (x+x)
        f = make_composition(rhs, set)
    else
        f = quote $(Expr(:tuple, values(membernames)...)) ->  $rhs end
    end
    if byrow & !isempty(set)
        f = quote PairsMacros.ByRow($f) end
    end
    return source, f, rhs ∉ set
end

# when Cols() implemented in DataFrames.jl, 
# @cols(f, r".*") could be used to return Cols(r".*") .=> f
export @rows, @cols

end