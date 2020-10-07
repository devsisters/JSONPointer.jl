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
    @test eltype(b) <: Dict{String, Any}
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

    data = Dict(p1 =>"this", p2 => 20)
    @test data[p1] == "this"
    @test data[p2] == 20

    @test_throws ErrorException data[p1] = 20
    @test_throws ErrorException data[p2] = "this"

    p1 = j"/a/1::array"
    p2 = j"/a/2::number"
    p3 = j"/b::array"

    data = Dict(p1 =>[10], p2 => 20,  p3 => ["this", "is"])
    @test data[p1] == Int[10]
    @test data[p2] == 20.
    @test data[p3] == ["this", "is"]

    @test_throws ErrorException data[p2] = [1000]
    @test_throws ErrorException data[p3] = "this"

    d = Dict(p1 => missing, p3 => missing)
    @test d[p1] == JSONPointer._null_value(p1)
    @test d[p3] == JSONPointer._null_value(p3)

    # TODO User Defined type
    struct Foo
    end
    # @test_broken j"/foo::Foo"

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
