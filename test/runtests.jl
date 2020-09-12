using Test, JSONPointer
using OrderedCollections

@testset "JSONPointer Basic" begin
    a = j"/a/1/c"
    b = j"/a/5"
    c = j"/a/2/d::Vector"
    d = j"/a/2/e::Vector{Int}"
    e = j"/a/2/f::Vector{Float64}"

    @test a.token == ("a", 1, "c")
    @test b.token == ("a", 5)
    @test c.token == ("a", 2, "d")
    @test eltype(c) <: Array
    @test eltype(d) <: Array{Int, 1}
    @test eltype(e) <: Array{Float64, 1}
end

@testset "construct Dict with JSONPointer" begin 
    p1 = j"/ba/1/a"
    p2 = j"/ba/2/a"

    data = Dict(p1 =>1, p2 => 2)
    @test data[p1] == 1
    @test data[p2] == 2
    @test haskey(data, p1)
    @test haskey(data, p2)
    @test !haskey(data, j"/x")
    @test !haskey(data, j"/ba/5")

    p1 = j"/a/1"
    p2 = j"/a/2/a"

    data = OrderedDict(p1 => "This", p2 => "Is my Data")
    @test data[p1] == "This"
    @test data[p2] == "Is my Data"

end

@testset "access deep nested object" begin 
    data = [Dict("a" => 10)]
    @test data[j"/1/a"] == 10

    p1 = j"/a/b/c/d/e/f/g/1/2/a/b/c"
    data = Dict(p1 => "sooo deep")
    @test data[p1] == "sooo deep"
    @test get(data, p1, missing) == "sooo deep"
    
    @test isa(data[j"/a/b/c/d/e/f/g"], Array)
    @test ismissing(data[j"/a/b/c/d/e/f/g/1/1"])
    
    @test get(data, j"/a/f", missing) |> ismissing
    @test get(data, j"/a/b/c/d/e/f/g/5", 10000) == 10000

    @test_throws KeyError data[j"/a/f"]
    @test_throws KeyError data[j"/x"]
    @test_throws BoundsError data[j"/a/b/c/d/e/f/g/5"]

    data = [[10, 20, 30, ["me"]]]
    @test data[j"/1"] == [10, 20, 30, ["me"]]
    @test data[j"/1/2"] == 20
    @test data[j"/1/4"] == ["me"]
    @test data[j"/1/4/1"] == "me"

    # need to add get for Array?
    @test_broken get(data, j"/1", missing) |> ismissing
end

@testset "grow obejct and array" begin 
    d = Dict(j"/a" => Dict())
    d[j"/a/b"] = []
    d[j"/a/b/10"] = 10 
    @test_throws Exception d[j"/a/5"] = 10 
    @test_throws Exception d[j"/a/b/gd"] = 10 

    @test isa(d[j"/a/b"], Array) 
    @test isa(d[j"/a/b/2"], Missing) 
end

@testset "Enforce type on JSONPointer" begin 
    p1 = j"/a/1::String"
    p2 = j"/a/2::Int"

    data = Dict(p1 =>"this", p2 => 20)
    @test data[p1] == "this"
    @test data[p2] == 20
   
    @test_throws ErrorException data[p1] = 20
    @test_throws ErrorException data[p2] = "this"

    p1 = j"/a/1::Vector{Int}"
    p2 = j"/a/2::Float64"
    p3 = j"/b::Vector{String}"

    data = Dict(p1 =>[10], p2 => 20,  p3 => ["this", "is"])
    @test data[p1] == Int[10]
    @test data[p2] == 20.
    @test data[p3] == ["this", "is"]

    @test_throws ErrorException data[p2] = [1000]
    @test_throws ErrorException data[p3] = "this"

    # TODO User Defined type
    struct Foo 
    end
    # @test_broken j"/foo::Foo"

end

@testset "error handling" begin
    p1 = j"/1/a"
    @test_throws MethodError Dict(p1 => 10)

    @test_throws ArgumentError j"a/b/c"
    @test_throws ArgumentError j"/a/0/1"
end

@testset "literal string" begin
    p1 = j"/\5"
    p2 = j"/\559"
    p3 = j"/\900/10"

    d = Dict(p1 => 1, p2 => 2, p3 => 3)
    @test d[p1] == 1
    @test d["5"] == 1
    @test d[p2] == 2
    @test d["559"] == 2

    @test d[p3] == 3 
    @test isa(d["900"], Array)
end