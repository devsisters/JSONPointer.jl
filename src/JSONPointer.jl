module JSONPointer

using DataStructures
import OrderedCollections

include("pointer.jl")
include("pointer_dict.jl")

export @j_str, PointerDict

end # module
