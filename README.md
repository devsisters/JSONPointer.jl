# JSONPointer
implementation of JSONPointer on Julia



## Overview
[JSONPointer](https://tools.ietf.org/html/rfc6901/) is a Unicode string 
containing a sequence of zero or more reference tokens, each prefixed
by a '/' (%x2F) character.


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

## Limitations
- Can only used on Dictionary with a 'String' key
- Supports Only 'Dict' and 'OrderedDict', but it can be extended for other 'AbstractDict' types. feel free to create a issue
