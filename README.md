# JSONPointer
![LICENSE MIT](https://img.shields.io/badge/license-MIT-brightgreen.svg?style=flat-square)
![Run CI on master](https://github.com/devsisters/JSONPointer.jl/workflows/Run%20CI%20on%20master/badge.svg)
[![Converage](https://devsisters.github.io/JSONPointer.jl/coverage/badge_linecoverage.svg)](https://devsisters.github.io/JSONPointer.jl/coverage/index)


implementation of JSONPointer on Julia

## Overview
[JSONPointer](https://tools.ietf.org/html/rfc6901/) is a Unicode string containing a sequence of zero or more reference tokens, each prefixed by a '/' (%x2F) character.  
**※ Note that Julia is using 1-based index and, copied JSONPointer token from other language will give you wrong data**

## Examples

**Constructing Dictionary**
```julia
using JSONPointer 

julia>p1 = j"/a/1/b"
      p2 = j"/a/2/b"
      data = Dict(p1 =>1, p2 => 2)
Dict{String,Any} with 1 entry:
  "a" => Any[Dict{String,Any}("b"=>1), Dict{String,Any}("b"=>2)]

```


**Accessing nested data**
```julia
using JSONPointer 

julia> arr = [[10, 20, 30, ["me"]]]
       arr[j"/1"] == [10, 20, 30, ["me"]]
       arr[j"/1/2"] == 20
       arr[j"/1/4"] == ["me"]
       arr[j"/1/4/1"] == "me"

julia> dict = Dict("a" => Dict("b" => Dict("c" => [100, Dict("d" => 200)])))
       dict[j"/a"]
       dict[j"/a/b"]
       dict[j"/a/b/c/1"]
       dict[j"/a/b/c/2/d"]
```

## Advanced
**Constructing Dictionary With Static type**

additionally, you can enforce type with '::T' at the end of pointer 
```julia
    p1 = j"/a::Vector{Int}"
    p2 = j"/b/2::String"
    data = Dict(p1 => [1,2,3], p2 => "Must be a String")
```

**String number as a key**
If you need to use a string number as key for dict, put '\' in front of a number 
```julia
    p1 = j"/\10"
    data = Dict(p1 => "this won't be a array")

    data[p1]
```



## Limitations
- Can only used on Dictionary with a 'String' key
- Supports Only 'Dict' and 'OrderedDict', but could be extended for other 'AbstractDict' types. feel free to create a issue
