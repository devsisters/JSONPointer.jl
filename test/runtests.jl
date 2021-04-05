using Test
using JSONPointer
using OrderedCollections

@testset "Basic Tests" begin
    doc = Dict(
        "foo" => ["bar", "baz"],
        "" => 0,
        "a/b" => 1,
        "c%d" => 2,
        "e^f" => 3,
        "g|h" => 4,
        "i\\j" => 5,
        "k\"l" => 6,
        " " => 7,
        "m~n" => 8
    )

    @test doc[j""] == doc
    @test doc[j"/foo"] == ["bar", "baz"]
    @test doc[JSONPointer.Pointer("/foo/0"; shift_index = true)] == "bar"
    @test doc[j"/foo/1"] == "bar"
    @test doc[j"/"] == 0
    @test doc[j"/a~1b"] == 1
    @test doc[j"/c%d"] == 2
    @test doc[j"/e^f"] == 3
    @test doc[j"/g|h"] == 4
    @test doc[JSONPointer.Pointer("/i\\j")] == 5
    @test doc[j"/k\"l"] == 6
    @test doc[j"/ "] == 7
    @test doc[j"/m~0n"] == 8

    for k in (
        j"",
        j"/foo",
        j"/foo/1",
        j"/",
        j"/a~1b",
        j"/c%d",
        j"/e^f",
        j"/g|h",
        JSONPointer.Pointer("/i\\j"),
        j"/k\"l",
        j"/ ",
        j"/m~0n",
    )
        @test haskey(doc, k)
    end
end

@testset "URI Fragment Tests" begin
    doc = Dict(
        "foo" => ["bar", "baz"],
        ""=> 0,
        "a/b"=> 1,
        "c%d"=> 2,
        "e^f"=> 3,
        "g|h"=> 4,
        "i\\j"=> 5,
        "k\"l"=> 6,
        " "=> 7,
        "m~n"=> 8,
    )

    @test doc[j"#"] == doc
    @test doc[j"#/foo"] == ["bar", "baz"]
    @test doc[JSONPointer.Pointer("#/foo/0"; shift_index = true)] == "bar"
    @test doc[j"#/foo/1"] == "bar"
    @test doc[j"#/"] == 0
    @test doc[j"#/a~1b"] == 1
    @test doc[j"#/c%25d"] == 2
    @test doc[j"#/e%5Ef"] == 3
    @test doc[j"#/g%7Ch"] == 4
    @test doc[j"#/i%5Cj"] == 5
    @test doc[j"#/k%22l"] == 6
    @test doc[j"#/%20"] == 7
    @test doc[j"#/m~0n"] == 8
end

@testset "WrongInputTests" begin
    @test_throws ArgumentError JSONPointer.Pointer("some/thing")
    doc = [0, 1, 2]
    @test_throws(
        ErrorException(
            "JSON pointer does not match the data-structure. I tried (and " *
            "failed) to index $(doc) with the key: a"
        ),
        doc[j"/a"],
    )
    @test_throws BoundsError doc[j"/10"]
end

@testset "JSONPointer Advanced" begin
    a = j"/a/2/d::array"
    b = j"/a/2/e::object"
    c = j"/a/2/f::boolean"

    @test a.tokens == ["a", 2, "d"]
    @test eltype(a) <: Vector{Any}
    @test eltype(b) <: OrderedDict{String, Any}
    @test eltype(c) <: Bool
end

@testset "construct Dict with JSONPointer" begin
    p1 = j"/a/1/b"
    p2 = j"/cd/2/ef"

    data = Dict(p1 =>1, p2 => 2)
    @test data[p1] == 1
    @test data[p2] == 2
    @test haskey(data, p1)
    @test haskey(data, p2)
    @test !haskey(data, j"/x")
    @test !haskey(data, j"/ba/5")

    p1 = j"/ab/1"
    p2 = j"/cd/2/ef"

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

    @test haskey(data, j"/a/b/c")
    @test haskey(data, j"/a/b/c/d")
    @test haskey(data, j"/a/b/c/d/e/f/g/1")
    @test !haskey(data, j"/a/b/c/d/e/f/g/2")

    @test isa(data[j"/a/b/c"], AbstractDict)
    @test isa(data[j"/a/b/c/d"], AbstractDict)
    @test isa(data[j"/a/b/c/d/e"], AbstractDict)
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

@testset "literal string for a Number" begin
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

@testset "unique" begin
    p = [j"/a", j"/b", j"/a"]
    up = unique(p)
    @test length(up) == 2
    @test j"/a" in up
    @test j"/b" in up
end

@testset "Failed setindex!" begin
    d = Dict("a" => [1])
    @test_throws ErrorException d[j"/a/b"] = 1
end

@testset "grow object and array" begin
    d = Dict(j"/a" => Dict())
    d[j"/a/b"] = []
    d[j"/a/b/2"] = 1
    d[j"/a/b/5"] = 2
    @test_throws Exception d[j"/a/5"] = "something"
    @test_throws Exception d[j"/a/b/gd"] = "nothing"

    @test isa(d[j"/a/b"], Array)
    @test isa(d[j"/a/b/1"], Missing)
end

@testset "Enforce type on JSONPointer" begin
    p1 = j"/a/1::string"
    p2 = j"/a/2::number"
    p3 = j"/a/3::object"
    p4 = j"/a/4::array"
    p5 = j"/a/5::boolean"
    p6 = j"/a/6::null"

    data = Dict(p1 =>"string", p2 => 1, p3 => Dict(), p4 => [], p5 => true, p6 => missing)
    @test data[p1] == "string"
    @test data[p2] == 1
    
    @test_throws ErrorException data[p1] = 1
    @test_throws ErrorException data[p2] = "string"
    
    d = Dict(p1 =>missing, p2 => missing, p3 => missing, p4 => missing, p5 => missing)
    @test d[p1] == ""
    @test d[p2] == 0
    @test isa(d[p3], OrderedDict)
    @test isa(d[p4], Array{Any, 1})
    @test d[p5] == false
end

@testset "Exceptions" begin
    # error on undefined datatype
    @test_throws ErrorException JSONPointer.Pointer("/a::nothing")
    @test_throws ErrorException JSONPointer.Pointer("/a/1::Int")

    # error for 0 based indexing 
    @test_throws ArgumentError JSONPointer.Pointer("/0")
    @test_throws ArgumentError JSONPointer.Pointer("/a/0")
    @test isa(JSONPointer.Pointer("/0"; shift_index = true), JSONPointer.Pointer)

end

@testset "Miscellaneous" begin 
    p1 = j"/a/b/1/c"

    @test p1 == j"/a/b/1/c"
    @test p1 != j"/b/a/1/c"

    arr = [1,2,3]
    haskey(arr, j"/1")
    !haskey(arr, j"/4")
end