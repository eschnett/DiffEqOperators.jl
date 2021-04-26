
function LinearAlgebra.mul!(x_temp::AbstractArray{Array{T,1},3}, A::CurlOperator, x::AbstractArray{Array{T,1},3}; overwrite = false) where {T<:Real}
    convolve_BC_left!(x_temp, x, A, overwrite = overwrite)
    convolve_interior!(x_temp, x, A, overwrite = overwrite)
    convolve_BC_right!(x_temp, x, A, overwrite = overwrite)
end

# mul! implementation for the case when output array contains vector elements 

function LinearAlgebra.mul!(x_temp::AbstractArray{Array{T,1}, N2}, A::DerivativeOperator{T,N}, M::AbstractArray{T,N2}; overwrite = true) where {T,N,N2}

    # Check that x_temp has valid dimensions, allowing unnecessary padding in M
    v = zeros(ndims(x_temp))
    v .= 2
    @assert all(([size(x_temp)...] .== [size(M)...])
        .| (([size(x_temp)...] .+ v) .== [size(M)...])
        )

    # Check that axis of differentiation is in the dimensions of M and x_temp
    ndims_M = ndims(M)
    @assert N <= ndims_M
    @assert size(x_temp, N) + 2 == size(M, N) # differentiated dimension must be padded

    alldims = [1:ndims(M);]
    otherdims = setdiff(alldims, N)

    idx = Any[first(ind) for ind in axes(M)]
    nidx = length(otherdims)

    dims_M = [axes(M)...]
    dims_x_temp = [axes(x_temp)...]
    minimal_padding_indices = map(enumerate(dims_x_temp)) do (dim, val)
        if dim == N || length(dims_x_temp[dim]) == length(dims_M[dim])
            Colon()
        else
            dims_M[dim][begin+1:end-1]
        end
    end
    minimally_padded_M = view(M, minimal_padding_indices...)

    itershape = tuple(dims_x_temp[otherdims]...)
    indices = Iterators.drop(CartesianIndices(itershape), 0)

    setindex!(idx, :, N)
    for I in indices
        # replace all elements of idx with corresponding elt of I, except at index N
        Base.replace_tuples!(nidx, idx, idx, otherdims, I)
        mul!(view(x_temp, idx...), A, view(minimally_padded_M, idx...), overwrite = true)
    end
end

function convolve_interior!(x_temp::AbstractArray{Array{T,1}, 3}, u::AbstractArray{Array{T,1},3}, A::CurlOperator; overwrite = false) where {T}
    
    s = size(x_temp)
    stencil_1 = A.ops[1].stencil_coefs
    stencil_2 = A.ops[2].stencil_coefs
    stencil_3 = A.ops[3].stencil_coefs

    coeff_1   = A.ops[1].coefficients
    coeff_2   = A.ops[2].coefficients
    coeff_3   = A.ops[3].coefficients

    bpc = A.ops[1].boundary_point_count
        
    e = begin #create unit CartesianIndex for each dimension
        out = Vector{CartesianIndex}(undef, 3)
        null = zeros(Int64, 3)
        for i in 1:3
            unit_i = copy(null)
            unit_i[i] = 1
            out[i] = CartesianIndex(Tuple(unit_i))
        end
        out
    end

    mid = div(A.ops[1].stencil_length,2)

    # Compute derivatives in particular dimensions and aggregate the outputs
    R1 = CartesianIndices((1+bpc : s[1]-bpc , 1 : s[2] , 1: s[3]))

    for I in R1
        x = zeros(T,3)
        cur_stencil_1 = eltype(stencil_1) <: AbstractArray ? stencil_1[I[1]-bpc] : stencil_1
        cur_coeff_1   = typeof(coeff_1)   <: AbstractArray ? coeff_1[I[1]] : true
        for idx in 1:(A.ops[1].stencil_length)
            x[2] += -cur_coeff_1*cur_stencil_1[idx]*u[I+e[1]*(idx-mid)][3]
            x[3] += cur_coeff_1*cur_stencil_1[idx]*u[I+e[1]*(idx-mid)][2]
        end
        x_temp[I] = x + !overwrite*x_temp[I]
    end

    R2 = CartesianIndices((1: s[1] , 1+bpc : s[2]-bpc , 1: s[3]))

    for I in R2
        x = zeros(T,3)
        cur_stencil_2 = eltype(stencil_2) <: AbstractArray ? stencil_2[I[2]-bpc] : stencil_2
        cur_coeff_2   = typeof(coeff_2)   <: AbstractArray ? coeff_2[I[2]] : true
        for idx in 1:(A.ops[2].stencil_length)
            x[1] += cur_coeff_2*cur_stencil_2[idx]*u[I+e[2]*(idx-mid)][3]
            x[3] += -cur_coeff_2*cur_stencil_2[idx]*u[I+e[2]*(idx-mid)][1]
        end
        x_temp[I] = x + !overwrite*x_temp[I]
    end

    R3 = CartesianIndices((1 : s[1] , 1 : s[2] , 1+bpc : s[3]-bpc))

    for I in R3
        x = zeros(T,3)
        cur_stencil_3 = eltype(stencil_3) <: AbstractArray ? stencil_3[I[3]-bpc] : stencil_3
        cur_coeff_3   = typeof(coeff_3)   <: AbstractArray ? coeff_3[I[3]] : true
        for idx in 1:(A.ops[3].stencil_length)
            x[1] += -cur_coeff_3*cur_stencil_3[idx]*u[I+e[3]*(idx-mid)][2]
            x[2] += cur_coeff_3*cur_stencil_3[idx]*u[I+e[3]*(idx-mid)][1]
        end
        x_temp[I] = x + !overwrite*x_temp[I]
    end
end

function convolve_BC_left!(x_temp::AbstractArray{Array{T,1}, 3}, u::AbstractArray{Array{T,1},3}, A::CurlOperator; overwrite = false) where {T}
    
    s = size(x_temp)
    stencil_1 = A.ops[1].low_boundary_coefs
    stencil_2 = A.ops[2].low_boundary_coefs
    stencil_3 = A.ops[3].low_boundary_coefs

    coeff_1   = A.ops[1].coefficients
    coeff_2   = A.ops[2].coefficients
    coeff_3   = A.ops[3].coefficients

    bpc = A.ops[1].boundary_point_count
    
    R1 = CartesianIndices((1 : bpc , 1:s[2] , 1:s[3]))
    
    e = begin #create unit CartesianIndex for each dimension
        out = Vector{CartesianIndex}(undef, 3)
        null = zeros(Int64, 3)
        for i in 1:3
            unit_i = copy(null)
            unit_i[i] = 1
            out[i] = CartesianIndex(Tuple(unit_i))
        end
        out
    end

    for I in R1
        x = zeros(T,3)
        cur_stencil_1 = stencil_1[I[1]]
        cur_coeff_1   = typeof(coeff_1)   <: AbstractArray ? coeff_1[I[1]] : coeff_1 isa Number ? coeff_1 : true
        for idx in 1:(A.ops[1].boundary_stencil_length)
            x[2] += -cur_coeff_1*cur_stencil_1[idx]*u[I+e[1]*(idx-I[1])][3]
            x[3] += cur_coeff_1*cur_stencil_1[idx]*u[I+e[1]*(idx-I[1])][2]
        end
        x_temp[I] = x + !overwrite*x_temp[I]
    end

    R2 = CartesianIndices((1:s[1] , 1:bpc , 1:s[3]))

    for I in R2
        x = zeros(T,3)
        cur_stencil_2 = stencil_2[I[2]]
        cur_coeff_2   = typeof(coeff_2)   <: AbstractArray ? coeff_2[I[2]] : coeff_2 isa Number ? coeff_2 : true
        for idx in 1:(A.ops[2].boundary_stencil_length)
            x[1] += cur_coeff_2*cur_stencil_2[idx]*u[I+e[2]*(idx-I[2])][3]
            x[3] += -cur_coeff_2*cur_stencil_2[idx]*u[I+e[2]*(idx-I[2])][1]
        end
        x_temp[I] = x + !overwrite*x_temp[I]
    end

    R3 = CartesianIndices((1:s[1] , 1:s[2] , 1:bpc))

    for I in R3
        x = zeros(T,3)
        cur_stencil_3 = stencil_3[I[3]]
        cur_coeff_3   = typeof(coeff_3)   <: AbstractArray ? coeff_3[I[3]] : coeff_3 isa Number ? coeff_3 : true
        for idx in 1:(A.ops[3].boundary_stencil_length)
            x[1] += -cur_coeff_3*cur_stencil_3[idx]*u[I+e[3]*(idx-I[3])][2]
            x[2] += cur_coeff_3*cur_stencil_3[idx]*u[I+e[3]*(idx-I[3])][1]
        end
        x_temp[I] = x + !overwrite*x_temp[I]
    end
end

function convolve_BC_right!(x_temp::AbstractArray{Array{T,1}, 3}, u::AbstractArray{Array{T,1},3}, A::CurlOperator; overwrite = false) where {T}
    
    s = size(x_temp)
    stencil_1 = A.ops[1].high_boundary_coefs
    stencil_2 = A.ops[2].high_boundary_coefs
    stencil_3 = A.ops[3].high_boundary_coefs

    coeff_1   = A.ops[1].coefficients
    coeff_2   = A.ops[2].coefficients
    coeff_3   = A.ops[3].coefficients

    bpc = A.ops[1].boundary_point_count
    bstl = A.ops[1].boundary_stencil_length
    R1 = CartesianIndices((s[1]-bpc+1 : s[1] , 1 : s[2] , 1 : s[3]))
    
    e = begin #create unit CartesianIndex for each dimension
        out = Vector{CartesianIndex}(undef, 3)
        null = zeros(Int64, 3)
        for i in 1:3
            unit_i = copy(null)
            unit_i[i] = 1
            out[i] = CartesianIndex(Tuple(unit_i))
        end
        out
    end

    for I in R1
        x = zeros(T,3)
        cur_stencil_1 = stencil_1[I[1] - s[1] + bpc]
        cur_coeff_1   = typeof(coeff_1)   <: AbstractArray ? coeff_1[I[1]] : coeff_1 isa Number ? coeff_1 : true
        for idx in 1:bstl
            x[2] += -cur_coeff_1*cur_stencil_1[idx]*u[I+e[1]*(s[1]-bstl+idx+2-I[1])][3]
            x[3] += cur_coeff_1*cur_stencil_1[idx]*u[I+e[1]*(s[1]-bstl+idx+2-I[1])][2]
        end
        x_temp[I] = x + !overwrite*x_temp[I]
    end

    R2 = CartesianIndices((1 : s[1] , s[2]-bpc+1 : s[2] , 1 : s[3]))

    for I in R2
        x = zeros(T,3)
        cur_stencil_2 = stencil_2[I[2] - s[2] + bpc]
        cur_coeff_2   = typeof(coeff_2)   <: AbstractArray ? coeff_2[I[2]] : coeff_2 isa Number ? coeff_2 : true
        for idx in 1:bstl
            x[1] += cur_coeff_2*cur_stencil_2[idx]*u[I+e[2]*(s[2]-bstl+idx+2-I[2])][3]
            x[3] += -cur_coeff_2*cur_stencil_2[idx]*u[I+e[2]*(s[2]-bstl+idx+2-I[2])][1]
        end
        x_temp[I] = x + !overwrite*x_temp[I]
    end

    R3 = CartesianIndices((1 : s[1] , 1 : s[2] , s[3]-bpc+1 : s[3]))

    for I in R3
        x = zeros(T,3)
        cur_stencil_3 = stencil_3[I[3] - s[3] + bpc]
        cur_coeff_3   = typeof(coeff_3)   <: AbstractArray ? coeff_3[I[3]] : coeff_3 isa Number ? coeff_3 : true
        for idx in 1:bstl
            x[1] += -cur_coeff_3*cur_stencil_3[idx]*u[I+e[3]*(s[3]-bstl+idx+2-I[3])][2]
            x[2] += cur_coeff_3*cur_stencil_3[idx]*u[I+e[3]*(s[3]-bstl+idx+2-I[3])][1]
        end
        x_temp[I] = x + !overwrite*x_temp[I]
    end
end