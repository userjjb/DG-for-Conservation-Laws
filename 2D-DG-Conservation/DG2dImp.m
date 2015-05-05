%Some terminology: the structured tensor grid means we can completely
%separate x and y components and discretize independently. They only couple
%when we calculate dw_p/dt at a point 'p' from the sum of each directions
%contribution, so dw_p/dt = dw_px/dt + dw_py/dt
%The set of colinear points along a coordinate direction will be called a
%"stream"

close all
clear all
clc

filename='FirstTest.mat';
saveQ=0;
%Solver parameters
alpha= 1;                           %Numerical flux param (1 upwind,0 CD)
N= 6;                               %Local vorticity poly order
M= 5;                               %Local velocity poly order
[RKa,RKb,RKc,nS]= LSRKcoeffs('NRK14C');
w_thresh=1E-6;
del=2*0.2^2;
delt= 0.01;
skip= 1;
EndTime=3;
DGmask='full';
BCtype= 'NoInflow';
NearRange=1;
TestCases=3;
%---Global domain initialization (parameters)------------------------------
B= [-1 1 -1 1];           %left, right, bottom, top
K= [10 10];               %Num elements along x,y

%Calculate all derived solver parameters (node/boundary/element positions
%and numbering, discrete norm, and pre-allocate vorticity/velocity vars
run('CalcedParams')
%Setup initial conditions at t_0
w=InitialConditions(w,TestCases,wxm,wym);

%Solver--------------------------------------------------------------------
run('SolverSetup')
tic
for t=0:delt:EndTime
    if mod(t,skip*delt)<delt
        run('PlotNSave')
    end
    
    %---Velocity eval of current timestep's vorticity config-----------
    v_xB(:)=0; v_yB(:)=0; v_xBF(:)=0; v_yBF(:)=0; v_xE(:)=0; v_yE(:)=0;
    w_elem=reshape(permute(reshape(wy,Np,K(2),Np,K(1)),[1 3 2 4]),1,Np^2,K(2)*K(1)); %Reshaped to col-wise element chunks
    w_tot=abs(permute(mtimesx(w_elem,QwPre'),[3 1 2])); %Sum of vorticity in each elem
    mask=find(w_tot>w_thresh); %Find "important" elements
    w_elemPre=bsxfun(@times,QwPre,w_elem(:,:,mask)); %Pre-multiply by quad weights for speed

    for it=1:length(mask)
        w_source=w_elemPre(:,:,it);
        source= mask(it);
        NsxS=Nsx(1:numS(source),source);
        NsyS=Nsy(1:numS(source),source);
        %Form specific source kernel by transforming the generalized source
        %kernel to the specific source loc
        kernel_xB= gkernel_xB(:, [1:Np*K(2)] +Np*(K(2)-Enumy(source)), [1:K(1)+1] +(K(1)-Enumx(source)) );
        kernel_yB= gkernel_yB(:, [1:Np*K(1)] +Np*(K(1)-Enumx(source)), [1:K(2)+1] +(K(2)-Enumy(source)) );
        %Calculate boundary velocities
        v_xBt= permute(mtimesx(w_source,kernel_xB),[2 3 1]); v_xB= v_xB + v_xBt;
        v_yBt= permute(mtimesx(w_source,kernel_yB),[3 2 1]); v_yB= v_yB + v_yBt;
        %Form far field boundary velocities due to source, add to
        %existing far field velocities. Be sure to leave out near-field
        %boundary velocities as these will be included in the whole
        %element evals
        v_xBFt= [v_xBt(EBl),v_xBt(EBr)]; v_xBFt(1,:,NsxS)=0; v_xBF= v_xBF + v_xBFt;
        v_yBFt= [v_yBt(EBb),v_yBt(EBt)]; v_yBFt(1,:,NsyS)=0; v_yBF= v_yBF + v_yBFt;

        %Assemble elementwise velocities for elements nearby the source
        v_xE(1,:,NsxS)= v_xE(1,:,NsxS)+ [v_xBt(EBl(NsxS)), mtimesx(w_source, kernel_x(:,:,1:numS(source),it)) ,v_xBt(EBr(NsxS))];
        v_yE(1,:,NsyS)= v_yE(1,:,NsyS)+ [v_yBt(EBb(NsyS)), mtimesx(w_source, kernel_y(:,:,1:numS(source),it)) ,v_yBt(EBt(NsyS))];
    end
    %---Velocity eval ends---------------------------------------------
        
    for i=1:nS
        St= t+RKc(i)*delt;              %Unused currently, St is the stage time if needed
        
        %---Advection------------------------------------------------------
        w_lx= mtimesx(Ll',wx);          %Left interpolated vorticity
        w_rx= mtimesx(Lr',wx);          %Right interpolated vorticity
        w_bx= mtimesx(Ll',wy);          %Bottom interpolated vorticity
        w_tx= mtimesx(Lr',wy);          %Top interpolated vorticity
        
        %Boundary fluxes
        if BCtype== 'NoInflow'
            v_xBC= v_xB; v_xBC(:,1)= min(v_xBC(:,1),0); v_xBC(:,end)= max(v_xBC(:,end),0);
            v_yBC= v_yB; v_yBC(1,:)= min(v_yBC(1,:),0); v_yBC(end,:)= max(v_yBC(end,:),0);
        end
        fl= abs( v_xBC(EBl) ).*( w_rx(x_km1).*(sign(v_xB(EBl))+alpha) + w_lx.*(sign(v_xB(EBl))-alpha) );
        fr= abs( v_xBC(EBr) ).*( w_rx.*(sign(v_xB(EBr))+alpha) + w_lx(x_kp1).*(sign(v_xB(EBr))-alpha) );
        fb= abs( v_yBC(EBb) ).*( w_tx(y_km1).*(sign(v_yB(EBb))+alpha) + w_bx.*(sign(v_yB(EBb))-alpha) );
        ft= abs( v_yBC(EBt) ).*( w_tx.*(sign(v_yB(EBt))+alpha) + w_bx(y_kp1).*(sign(v_yB(EBt))-alpha) );
        
        %Nodal total surface flux
        SurfFlux_x=bsxfun(@times,fr,LrM)-bsxfun(@times,fl,LlM);
        SurfFlux_y=bsxfun(@times,ft,LrM)-bsxfun(@times,fb,LlM);
        %Nodal stiffness eval
        Stiff_x= mtimesx(v_xBF,mtimesx(QwSMlow,wx));
        Stiff_x= Stiff_x + mtimesx(v_xE,mtimesx(QwSM,wx));
        Stiff_y= mtimesx(v_yBF,mtimesx(QwSMlow,wy));
        Stiff_y= Stiff_y + mtimesx(v_yE,mtimesx(QwSM,wy));

        wx_dt= permute(Stiff_x-SurfFlux_x,[4 1 3 2]); %Reshape to match wx
        wy_dt= reshape(reshape(Stiff_y-SurfFlux_y,K(2),[])',Np,1,[]); %Reshape to match wx
        
        k2= RKa(i)*k2 + delt*(wx_dt+wy_dt);
        wx= wx+RKb(i)*k2;
        wy= reshape(reshape(wx,K(1)*Np,[])',Np,1,[]); %Reshape wx to match global node ordering
    end
end
if saveQ; save(filename,'wxt','setup'); end