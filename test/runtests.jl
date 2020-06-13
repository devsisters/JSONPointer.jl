using Test, JSONPointer
using OrderedCollections

# construct
p1 = j"/ba/1/a"
p2 = j"/ba/2/a"

data = Dict()
data[p1] = 1
data[p2] = 2


data = OrderedDict()
data[p1] = 1
data[p2] = 2


# TODO? Construct purely from JSONPointer?
p1 = j"/1/a"
p2 = j"/2/a"


