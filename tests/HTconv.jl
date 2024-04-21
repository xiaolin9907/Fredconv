module HTconv

export fred_HT

using FFTW, FastTransforms, SparseArrays, LinearAlgebra, BandedMatrices, FillArrays
function fred_HT(fe, ge, r)
    # Caculating the Fredholm convolution using the method of Hale and Townsend given in "An algorithm for the convolution of Legendre series", SIAM Journal on Scientific Computing, Vol. 36, No. 3, pages A1207-A1220, 2014.
	
    # We have only implemented the H-T method for the cases of r being an integer. This program is for benchmarking only.

    # preparation:
    M = length(fe)                              # Length of f
    N = length(ge)                              # Length of g
    a = -r-1:2:r-3                              # Partion of f
    l = length(a)                               # Number of patches required
    x = r.*sin.(pi.*(-N+1:2:N-1)./(2*N))        # Chebyshev grid for interior
    y = 0*x                                     # Initialise values in the interior
    map = (x, a, b) -> (x .- a)./(b - a) .- (b .- x)./(b - a)

    fk1 = restrict(fe, [a[1] a[1]+2], r)        # f on the left subdomain
    y1 = rec(fk1, ge, 1)                        # Left triangle 
    for k in 1:l
        fk2 = restrict(fe, [a[k]+2 a[k]+4], r)  # f on the right subdomain
        y2 = rec(fk2, ge, -1)                   # Right triangle

        ind = ((a[k]+1) .<= x) .& (x .< (a[k]+3)) # Locate the grid values in [a[k]+1, a[k]+3]
        z = map(x[ind], a[k]+1, a[k]+3)         # Map to [-1,1]
        tmp1 = ClenshawLegendre(z, y1)          # Eval via recurrence
        tmp2 = ClenshawLegendre(z, y2)
        y[ind] = y[ind] + tmp1 + tmp2           # Append
        fk2 = fk1
    end
    yc = vals2coeffs(y)                         
    return yc  
end

function rec(alp, bet, sgn)
    # Compute the Legendre coefficients of the convolution on L/R piece.
    # See Theorem 4.1 of paper.

    # Better computational efficiency is achieved when g has the lower degree:
    if length(alp) < length(bet)
        tmp = alp
        alp = bet
        bet = tmp
    end

    M = length(alp)
    N = length(bet)

    # Maximum degree of result:
    MN = M + N

    # Pad to make length n + 1.
    alpha = zeros(MN)
    view(alpha, 1:M) .= alp

    if sgn == 1
        alpha = -alpha;
    end

    # S represents multiplication by 1/z in spherical Bessel space:
    S = BandedMatrix(-1 => 1 ./ (2*(0:(MN-2)) .+ 1), 0 => Fill(0, MN), 1 => -1 ./ (2*(1:MN-1) .+ 1))
    view(S, 1, 1) .= -sgn
    T = zeros(M+N, N)

    # First column:
    vNew = S*alpha
    v = vNew
    view(T,:,1) .= vNew
    if ( N == 1 )
        return T
    end

    # Secend column
    vNew = S*v + sgn*v
    vOld = v
    v = vNew
    view(vNew,1) .= 0
    view(T,:,2) .= vNew

    # Loop over remaining columns using recurrence:
    for n = 3:N
        mul!(vNew, S, v, 2*n-3, false)
        axpy!(true, vOld,vNew)
        # vNew = (2*n-3) .* (S * v) .+ vOld; 
        view(vNew,1:n-1) .= 0;                 
        view(T,:,n) .= vNew;
        vOld = v;
        v = vNew;
        
    end
    for i = 1:N
        j = i+1:N
        lmul!((-1)^(i) * (2*i-1), view(T, j, i))
        ldiv!(Diagonal(2 * j .- 1), view(T, j, i))
        lmul!(Diagonal((-1).^(j)), view(T, j, i))
    end
    return T * bet

end
##########################################################################################################

function restrict(fe,dom,r)
    # restrict f on dom where supp(f) = [-r, r].
    n = length(fe)                        # Length of fe
    x = sin.(LinRange(-pi/2, pi/2, n))    # Chebpts on [-1, 1]
    x = ((dom[1] + dom[2]) .+ (dom[2] - dom[1]) .* x) ./ (2*(r + 1)) # Chebpts on dom
    y = ClenshawLegendre(x, fe)           # Function values on x
    y = vals2coeffs(y')                   # New Chebyshev coefficients on dom
    loc = findlast(abs.(y) .> 1e-15)         
    y = cheb2leg(y[1:min(loc, floor(Int64, length(y)/(r + 1)))]);  # New Legendre coefficients on dom
    return y
end
##########################################################################################################

function ClenshawLegendre(x, alpha)   
    # Evaluate a Legendre expansion with coefficient alpha at x. 
    n = length(alpha); 
    b_old = zero(x); 
    b_cur = zero(x); 
    b_new = zero(x);
    for k = (n-1):-1:1
        b_new, b_cur, b_old = b_old, b_new, b_cur
        broadcast!(*, b_new, x, b_cur)
        axpby!(-(k+1)/(k+2), b_old, (2k+1)/(k+1), b_new)
        broadcast!(+, b_new, b_new, alpha[k+1])
    end
    val = alpha[1] .+ x.*b_new .- 0.5.*b_cur; 
    return val
end
##########################################################################################################

function vals2coeffs(values)
    # Converts the Chebyshev point values to the Chebyshev coefficients
    n = length(values)
    tmp = [values[n:-1:2]; values[1:n-1]];
    coeffs = ifft(tmp);
    coeffs = real(coeffs);
    coeffs = coeffs[1:n];
    coeffs[2:n-1] = 2*coeffs[2:n-1];
    return coeffs
end

end