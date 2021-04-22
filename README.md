[![Build status](https://github.com/matthieugomez/PairsMacros.jl/workflows/CI/badge.svg)](https://github.com/matthieugomez/PairsMacros.jl/actions)

PairsMacros.jl
=============

This package exports two macros: 
- `@cols` to make it easier to construct pairs of the form `source => function => target`. 
- `@rows` to make it easier to construct pairs of the form `source => ByRow(function) => target`. 

These macros can be used within DataFrames.jl  `transform`, `select`, `subset`, etc. It is a minimal alternative to [DataFramesMeta.jl](https://github.com/JuliaData/DataFramesMeta.jl).

## Syntax
```julia
using  PairsMacros
@cols z = sum(x)
#> [:x] => sum => :z
@rows z = x + y
#> [:x, :y] => ByRow(+) => :z
```


Use `$` to substitute the name of certain columns by symbols
```julia
u = :y
@cols z = sum($u)
#> [:y] => sum => :z
@cols $u = sum(x)
#> [:x] => sum => :y
u = "my variable name"
@cols z = sum($u)
"my variable name" => sum => :z
```

Use `esc` to denote variables that do not refer to columns
```julia
u = [0.25, 0.75]
@cols z = quantile(y, esc(u))
#> [:y] => (x -> quantile(x, u)) => :z
@cols z = map(esc(cos), y)
#> [:y] => (x -> map(cos, x)) => :z
@rows z = tryparse(esc(Float64), y)
#> [:y] => ByRow(x -> tryparse(Float64, x)) => :z
```


## Example
Use `PairsMacros` in conjunction with `DataFrames` and `Chain`:
```julia
using DataFrames, Chain, Statistics, PairsMacros
df = DataFrame(a = repeat(1:5, outer = 20),
               b = repeat(["a", "b", "c", "d"], inner = 25),
               x = repeat(1:20, inner = 5))
transform(@rows y = 10 * x)
```
Use `Chain` for a sequence of transformations:
```julia
x_thread = @chain df begin
    transform(@rows y = 10 * x)
    subset(@rows a > 2)
    groupby(:b)
    combine(@cols meanX = mean(x) meanY = mean(y))
    sort(:meanX)
    select(@cols meanX meanY var = b)
end
```



## Details
All symbols are assumed to refer to columns, with the exception of:
- symbol `missing`
- first `args` of a `:call` or `:.` expression (e.g. function calls)
- arguments inside of a splicing/interpolation expression `$()`
- arguments inside  `esc()`
