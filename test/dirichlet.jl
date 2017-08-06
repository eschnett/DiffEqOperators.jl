using Base.Test
using FactCheck

context("Dirichlet0 Boundary Conditions:")do
    N = 100
    h_inv = 1/(N-1)
    d_order = 2
    approx_order = 2
    x = collect(1:h_inv:N).^2
    A = DiffEqLinearOperator{Float64}(2,2,1/99,length(x),:Dirichlet0,:Dirichlet0,BC=(0.0,0.0))
    boundary_points = A.boundary_point_count
    res = A*x
    @test res[boundary_points[1] + 1: N - boundary_points[2]] ≈ 2.0*ones(N - sum(boundary_points));

    N = 1000
    d_order = 4
    approx_order = 10
    y = collect(1:1.0:N).^4 - 2*collect(1:1.0:N).^3 + collect(1:1.0:N).^2;
    A = DiffEqLinearOperator{Float64}(d_order,approx_order,1.0,N,:Dirichlet0,:Dirichlet0,BC=(0.0,0.0))
    boundary_points = A.boundary_point_count
    res = A*y
    @test res[boundary_points[1] + 1: N - boundary_points[2]] ≈ 24.0*ones(N - sum(boundary_points)) atol=10.0^-1; # Float64 is less stable

    A = DiffEqLinearOperator{BigFloat}(d_order,approx_order,one(BigFloat),N,:Dirichlet0,:Dirichlet0,BC=(0.0,0.0))
    y = convert(Array{BigFloat, 1}, y)
    res = A*y
    @test res[boundary_points[1] + 1: N - boundary_points[2]] ≈ 24.0*ones(N - sum(boundary_points)) atol=10.0^-approx_order;
end