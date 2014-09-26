function [Ld_n] = LagBasisD_n(N,n)
    [Qx,Qw]=GLquad(N);

    NOn=[1:n-1,n+1:N]; %The Lagrange bases don't include one for point 'n'
    for i=1:N
        NOni=NOn(not(NOn==i)); %The derivative can't include the evaluated point 'i'
        dLagBas_fun = @(x) prod( bsxfun(@minus,x,Qx(NOni)) )./prod( Qx(n)-Qx(NOn) );
        if not(i==n) %Every eval point except the one the basis is built on
            Ld_n(i) = dLagBas_fun(Qx(i));
        elseif i==n %Specially handle the evaluation of the point the basis is built on
            Ld_n(i) = sum( 1./( Qx(i)-Qx(NOn) ) );
        end
    end
end