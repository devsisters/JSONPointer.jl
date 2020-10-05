const TOKEN_PREFIX = '/'

macro j_str(token) 
    Pointer(token) 
end

"""
    Pointer(token)

A JSON Pointer is a Unicode string containing a sequence of zero or more reference tokens, each prefixed
by a '/' (%x2F) character.

Follows IETF JavaScript Object Notation (JSON) Pointer https://tools.ietf.org/html/rfc6901 

- Index numbers starts from '1' instead of '0'  
- User can declare type with '::T' notation at the end 

# Arguments
- `shift_index` : shift given index by 1 for compatibility with original JSONPointer

"""
struct Pointer{T}
    token::Tuple

    Pointer{T}(token::Tuple) where T = new{T}(token)
    function Pointer(token::AbstractString; shift_index = false)
        # URI Fragment
        if startswith(token, "#")
            token = token[2:end]
            token = unescape_jpath(token)
        end
        
        if isempty(token)
            return Pointer{Nothing}(tuple(""))
        end
        if !startswith(token, TOKEN_PREFIX) 
            throw(ArgumentError("JSONPointer must starts with '$TOKEN_PREFIX' prefix"))
        end
        
        T = Any
        jk = convert(Array{Any, 1}, split(chop(token; head=1, tail=0), TOKEN_PREFIX))
        if occursin("::", jk[end])
            x = split(jk[end], "::")
            jk[end] = x[1]
            T = (x[2] == "Vector" ? "Vector{Any}" : x[2]) |> Meta.parse |> eval
        end
        @inbounds for i in 1:length(jk)
            if occursin(r"^\d+$", jk[i]) # index of a array
                jk[i] = if shift_index 
                    parse(Int, string(jk[i])) + 1
                else 
                    parse(Int, string(jk[i]))
                end
                
                if iszero(jk[i]) 
                    throw(ArgumentError("Julia uses 1-based indexing, use '1' instead of '0'"))
                end
            elseif occursin(r"^\\\d+$", jk[i]) # literal string for a number
                jk[i] = chop(jk[i]; head=1, tail=0)
            elseif occursin("~", jk[i]) 
                jk[i] = replace(replace(jk[i], "~0" => "~"), "~1" => "/")
            end
        end
        new{T}(tuple(jk...)) 
    end
end

"""
    unescape_jpath(raw::String)

Transform escaped characters in JPaths back to their original value.
https://tools.ietf.org/html/rfc6901
"""
function unescape_jpath(raw::AbstractString)
    m = match(r"%([0-9A-F]{2})", raw)
    if m !== nothing
        for c in m.captures
            raw = replace(raw, "%$(c)" => Char(parse(UInt8, "0x$(c)")))
        end
    end
    return raw
end


""" 
    null_value(p::Pointer{T}) where T
    null_value(::Type{T}) where T

provide appropriate value for 'T'
'Real' return 'zero(T)' and 'AbstractString' returns '""'

If user wants different null value for 'T' override 'null_value(::Type{T})' method 

"""
null_value(p::Pointer) = null_value(eltype(p))
null_value(::Type{T}) where T = missing 
function null_value(::Type{T}) where T <: Array
    eltype(T) <: Real ? eltype(T)[] : 
    eltype(T) <: AbstractString ? eltype(T)[] :
    Any[]
end

for T in (Dict, OrderedDict)
    @eval begin 
        function $T{K,V}(kv::Pair{<:Pointer,V}...) where K<:Pointer where V
            $T{String,Any}()
        end

        Base.haskey(dict::$T{K,V}, p::Pointer) where {K, V} = haskey_by_pointer(dict, p)
        Base.getindex(dict::$T{K,V}, p::Pointer) where {K, V} = getindex_by_pointer(dict, p)
        Base.setindex!(dict::$T{K,V}, v, p::Pointer) where {K, V} = setindex_by_pointer!(dict, v, p)
        Base.get(dict::$T{K,V}, p::Pointer, default) where {K, V} = get_by_pointer(dict, p, default)

        # Base.setindex!(dict::$T{K,V}, v, p::Pointer) where {K <: Integer, V} = setindex_by_pointer!(dict, v, p)
    end
end
Base.getindex(A::AbstractArray, p::Pointer{Any}) = getindex_by_pointer(A, p)
Base.haskey(A::AbstractArray, p::Pointer) = getindex_by_pointer(A, p)

function Base.unique(arr::Array{Pointer, N}) where N
    out = deepcopy(arr)
    if isempty(arr)
        return out
    end

    pointers = getfield.(arr, :token)
    if allunique(pointers)
        return out 
    end 

    delete_target = Int[]
    @inbounds for p in pointers 
        indicies = findall(el -> el == p, pointers)
        if length(indicies) > 1 
            append!(delete_target, indicies[1:end-1])
        end
    end
    deleteat!(out, unique(delete_target))
end


haskey_by_pointer(collection, p::Pointer{Nothing}) = true
function haskey_by_pointer(collection, p::Pointer)::Bool
    b = true
    val = collection
    @inbounds for (i, k) in enumerate(p.token)
        if haskey_by_pointer(val, k)
            val = getindex(val, k)
        else
            b = false 
            break 
        end
    end
    return b
end
function haskey_by_pointer(collection, k)::Bool
    b = false
    if isa(collection, Array)
        if isa(k, Integer)
            if length(collection) >= k
                b = true
            end
        end
    else         
        if !isa(k, Integer)
            if haskey(collection, k)
                b = true
            end
        end
    end
    return b
end

function getindex_by_pointer(collection, p::Pointer{Nothing})
    collection
end
function getindex_by_pointer(collection, p::Pointer)    
    getindex_by_pointer(collection, p.token)
end

function getindex_by_pointer(collection, tokens::Tuple{<:Any})    
    getindex(collection, tokens[1])
end
function getindex_by_pointer(collection, tokens::Tuple{<:Any, <:Any})    
    getindex(getindex(collection, tokens[1]), tokens[2])
end
function getindex_by_pointer(collection, tokens::Tuple{<:Any, <:Any, <:Any})    
    getindex(getindex(getindex(collection, tokens[1]), tokens[2]), tokens[3])
end
function getindex_by_pointer(collection, tokens::Tuple{<:Any, <:Any, <:Any, <:Any})    
    getindex(getindex(getindex(getindex(collection, tokens[1]), tokens[2]), tokens[3]), tokens[4])
end
function getindex_by_pointer(collection, tokens::Tuple{<:Any, <:Any, <:Any, <:Any, <:Any})    
    getindex(getindex(getindex(getindex(getindex(collection, tokens[1]), tokens[2]), tokens[3]), tokens[4]), tokens[5])
end
function getindex_by_pointer(collection, tokens::Tuple{<:Any, <:Any, <:Any, <:Any, <:Any, <:Any})    
    getindex(getindex(getindex(getindex(getindex(getindex(collection, tokens[1]), tokens[2]), tokens[3]), tokens[4]), tokens[5]), tokens[6])
end
function getindex_by_pointer(collection, tokens::Tuple)
    val = getindex_by_pointer(collection, tokens[1:6])
    for i in 7:length(tokens)
        val = getindex(val, tokens[i])
    end
    val
end


function get_by_pointer(collection, p::Pointer, default)
    if haskey_by_pointer(collection, p)
        getindex_by_pointer(collection, p)
    else 
        default
    end
end

function setindex_by_pointer!(collection::T, v, p::Pointer{U}) where {T <: AbstractDict, U}
    v = ismissing(v) ? null_value(p) : v
    if !isa(v, U) && 
        try 
            v = convert(eltype(p), v)
        catch e 
            msg = isa(v, Array) ? "Vector" : "Any"
            error("$v is not valid value for $p use '::$msg' if you don't need static type")
            throw(e)
        end
    end
    prev = collection

    @inbounds for (i, k) in enumerate(p.token)
        if typeof(prev) <: AbstractDict
            DT = typeof(prev)
        else 
            DT = OrderedDict{String, Any}
        end

        if isa(prev, Array)
            if !isa(k, Integer)
                throw(MethodError(setindex!, k))
            end 
            grow_array!(prev, k)
        else 
            if isa(k, Integer)
                throw(MethodError(setindex!, k))
            end
            if !haskey(prev, k)
                setindex!(prev, missing, k)
            end
        end

        if i < length(p) 
            tmp = getindex(prev, k)
            if ismissing(tmp)
                next_key = p.token[i+1]
                if isa(next_key, Integer)
                    new_data = Array{Any,1}(missing, next_key)
                else 
                    new_data = DT(next_key => missing)
                end
                setindex!(prev, new_data, k)
            end
            prev = getindex(prev, k)
        end
    end
    setindex!(prev, v, p.token[end])
end

function grow_array!(arr::Array{T, N}, target_size) where T where N 
    x = target_size - length(arr) 
    if x > 0 
        if T <: Real 
            new_arr = similar(arr, x)
            new_arr .= zero(T)
        elseif T == Any 
            new_arr = similar(arr, x)
            new_arr .= missing 
        else 
            new_arr = Array{Union{T, Missing}}(undef, x)
            new_arr .= missing 
        end
        append!(arr, new_arr)
    end
    return arr
end

Base.length(x::Pointer) = length(x.token)
Base.eltype(x::Pointer{T}) where T = T

function Base.show(io::IO, x::Pointer{T}) where T
    print(io, 
    "JSONPointer{", T, "}(\"/", join(x.token, "/"), "\")")
end

function Base.show(io::IO, x::Pointer{Nothing})
    print(io, "JSONPointer{Nothing}(\"\")")
end
