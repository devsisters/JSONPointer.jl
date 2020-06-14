using Test, JSONPointer
using OrderedCollections

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
    p3 = j"/a/3/k::Dict"
    p4 = j"/b::Vector{String}"

    data = Dict(p1 =>[10], p2 => 20, p3 => Dict(), p4 => ["this", "is"])
    @test data[p1] == Int[10]
    @test data[p2] == 20.
    @test isa(data[p3], Dict)
    @test data[p4] == ["this", "is"]

    @test_throws ErrorException data[p3] = [100]
    @test_throws ErrorException data[p4] = "this"
end

@testset "error handling" begin
    p1 = j"/1/a"
    @test_throws MethodError Dict(p1 => 10)

end


function foo(xs::(Pair{K,V} where K <: JSONPointer.Pointer where V)...) 
    @show "OK?"
end
function foo(xs::Pair{K,V}...) where K where V 
    @show "im not"
    @show typeof.(xs)
end
