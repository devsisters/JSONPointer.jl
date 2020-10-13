struct PointerDict
    d::AbstractDict{K,V} where {K,V}

    PointerDict() = new(Dict{String,Any}())
    function PointerDict(ps::Pair{Pointer, V}...) where V 
        d = Dict{String, Any}()
        for kv in ps
            _setindex!(d, v, k)
        end
        new(d)
    end    
end
PointerDict(kv::AbstractArray{Pair{K,V}}) where {K,V}  = PointerDict(kv...)

# function PointerDict(ps::Pair...)
#     md = Dict(ps...)
#     return PointerDict(md)
# end
function PointerDict(kv::Pair{Pointer, V}) where V 
    d = Dict{String, Any}()
    _setindex!(d, kv[2], kv[1])
    d
end


## Functions

## Most functions are simply delegated to the wrapped Dict
DataStructures.@delegate PointerDict.d [Base.get, Base.get!, Base.getkey,
                        Base.length, Base.isempty, Base.eltype,
                        Base.iterate, Base.keys, Base.values, sizehint!, 
                        Base.copy, Base.empty, Base.delete!, Base.empty!,
                        Base.in, Base.pop!, Base.push!, Base.count, 
                        Base.size]

# ==============================================================================
Base.haskey(::PointerDict, ::Pointer{Nothing}) = true

function Base.haskey(collection::PointerDict, p::Pointer)
    for token in p.tokens
        if !_haskey(collection, token)
            return false
        end
        collection = _checked_get(collection, token)
    end
    return true
end

_haskey(collection::PointerDict, token::String) = _haskey(collection.d, token)
_haskey(collection::AbstractDict, token::String) = haskey(collection, token)
function _haskey(collection::AbstractArray, token::Int)
    return 1 <= token <= length(collection)
end

# ==============================================================================

Base.getindex(collection::PointerDict, i) = getindex(collection.d, i)
Base.getindex(collection::PointerDict, ::Pointer{Nothing}) = collection

function Base.getindex(collection::PointerDict, p::Pointer)
    return _getindex(collection.d, p.tokens)
end

function _getindex(collection::AbstractDict, tokens::Vector{Union{String, Int}})
    for token in tokens
        collection = _checked_get(collection, token)
    end
    return collection
end

# ==============================================================================
_checked_get(collection::PointerDict, token::String) = _checked_get(collection.d, token)
_checked_get(collection::AbstractDict, token::String) = collection[token]
_checked_get(collection::AbstractArray, token::Int) = collection[token]

function _checked_get(collection, token)
    error(
        "JSON pointer does not match the data-structure. I tried (and " *
        "failed) to index $(collection) with the key: $(token)"
    )
end

function Base.setindex!(
    collection::PointerDict, v, p::Pointer{U}
) where {U}
    v = _convert_v(v, p)
    prev = collection
    for (i, token) in enumerate(p.tokens)
        _prep_prev(prev, token)
        if i < length(p)
            if ismissing(_checked_get(prev, token))
                setindex!(prev, _new_data(prev, p.tokens[i + 1]), token)
            end
            prev = _checked_get(prev, token)
        end
    end
    return setindex!(prev, v, p.tokens[end])
end