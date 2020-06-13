using Test, JSONPointer
using OrderedCollections

# construct
@testset "construct Dict with JSONPointer" begin 
    p1 = j"/ba/1/a"
    p2 = j"/ba/2/a"

    data = Dict(p1 =>1, p2 => 2)
    @test data[p1] == 1
    @test data[p2] == 2

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
    @test isa(data[j"/a/b/c/d/e/f/g"], Array)
    @test ismissing(data[j"/a/b/c/d/e/f/g/1/1"])

    data = [[10, 20, 30, ["me"]]]
    @test data[j"/1"] == [10, 20, 30, ["me"]]
    @test data[j"/1/2"] == 20
    @test data[j"/1/4"] == ["me"]
    @test data[j"/1/4/1"] == "me"

end

@testset "error handling" begin
    p1 = j"/1/a"
    @test_throws ArgumentError Dict(p1)

end


