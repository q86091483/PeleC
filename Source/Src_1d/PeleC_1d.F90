subroutine pc_umdrv(is_finest_level, time, &
                    lo, hi, domlo, domhi, &
                    uin, uin_l1, uin_h1, &
                    uout, uout_l1, uout_h1, &
                    q, q_l1, q_h1, &
                    qaux, qa_l1, qa_h1, &
                    srcQ, srQ_l1, srQ_h1, &
                    update, updt_l1, updt_h1, &
                    bcMask, bcMask_l1, bcMask_h1, &
                    delta, dt, &
                    flux, flux_l1, flux_h1, &
                    pradial, p_l1, p_h1, &
                    area, area_l1, area_h1, &
                    dloga, dloga_l1, dloga_h1, &
                    vol, vol_l1, vol_h1, &
                    courno, verbose, &
                    mass_added_flux, xmom_added_flux, ymom_added_flux, zmom_added_flux, &
                    E_added_flux, mass_lost, xmom_lost, ymom_lost, zmom_lost, &
                    eden_lost, xang_lost, yang_lost, zang_lost) bind(C, name="pc_umdrv")

  use meth_params_module, only : QVAR, QU, QV, QW, QPRES, &
                                 NQAUX, NVAR, NHYP, use_flattening, &
                                 NGDNV, GDU, GDPRES, first_order_hydro
  use bl_constants_module, only : ZERO, HALF, ONE
  use advection_util_module, only : compute_cfl
  use flatten_module, only : uflaten
  use prob_params_module, only : coord_type
  use advection_module  , only : umeth1d, consup
  implicit none

  integer, intent(in) :: is_finest_level
  integer, intent(in) :: lo(1), hi(1), verbose
  integer, intent(in) :: domlo(1), domhi(1)
  integer, intent(in) :: uin_l1, uin_h1
  integer, intent(in) :: uout_l1, uout_h1
  integer, intent(in) :: q_l1, q_h1
  integer, intent(in) :: qa_l1, qa_h1
  integer, intent(in) :: srQ_l1,srQ_h1
  integer, intent(in) :: updt_l1, updt_h1
  integer, intent(in) :: flux_l1, flux_h1
  integer, intent(in) :: p_l1, p_h1
  integer, intent(in) :: area_l1, area_h1
  integer, intent(in) :: dloga_l1, dloga_h1
  integer, intent(in) :: vol_l1, vol_h1
  integer, intent(in) :: bcMask_l1, bcMask_h1
  
  integer, intent(inout) :: bcMask(bcMask_l1:bcMask_h1,2)
  double precision, intent(in) ::      uin(  uin_l1:  uin_h1,NVAR)
  double precision, intent(inout) ::  uout( uout_l1: uout_h1,NVAR)
  double precision, intent(inout) ::     q(    q_l1:    q_h1,QVAR)
  double precision, intent(in) ::     qaux(   qa_l1:   qa_h1,NQAUX)
  double precision, intent(in) ::     srcQ(  srQ_l1:  srQ_h1,QVAR)
  double precision, intent(inout) :: update(updt_l1: updt_h1,NVAR)
  double precision, intent(inout) ::  flux( flux_l1: flux_h1,NVAR)
  double precision, intent(inout) :: pradial(  p_l1:   p_h1)
  double precision, intent(in) :: area( area_l1: area_h1     )
  double precision, intent(in) :: dloga(dloga_l1:dloga_h1     )
  double precision, intent(in) ::   vol(  vol_l1: vol_h1      )
  double precision, intent(in) :: delta(1), dt, time
  double precision, intent(inout) :: courno

  double precision, intent(inout) :: E_added_flux, mass_added_flux
  double precision, intent(inout) :: xmom_added_flux, ymom_added_flux, zmom_added_flux
  double precision, intent(inout) :: mass_lost, xmom_lost, ymom_lost, zmom_lost
  double precision, intent(inout) :: eden_lost, xang_lost, yang_lost, zang_lost

  ! Automatic arrays for workspace
  double precision, allocatable:: flatn(:)
  double precision, allocatable:: div(:)
  double precision, allocatable:: pdivu(:)

  ! Edge-centered primitive variables (Riemann state)
  double precision, allocatable :: q1(:,:)

  double precision :: dx

  integer i,ngf, ngq

  integer ::  uin_lo(1),  uin_hi(1)
  integer :: uout_lo(1), uout_hi(1)
  integer :: q_lo(1), q_hi(1)

  integer :: lo_3D(3), hi_3D(3)
  integer :: q_lo_3D(3), q_hi_3D(3)
  integer :: uin_lo_3D(3), uin_hi_3D(3)
  double precision :: dx_3D(3)

  uin_lo  = [uin_l1]
  uin_hi  = [uin_h1]

  uout_lo = [uout_l1]
  uout_hi = [uout_h1]

  ngq = NHYP
  ngf = 1

  q_lo = [q_l1]
  q_hi = [q_h1]

  lo_3D   = [lo(1), 0, 0]
  hi_3D   = [hi(1), 0, 0]
  q_lo_3D = [q_l1, 0, 0]
  q_hi_3D = [q_h1, 0, 0]
  uin_lo_3D = [uin_l1, 0, 0]
  uin_hi_3D = [uin_h1, 0, 0]
  dx_3D   = [delta(1), ZERO, ZERO]

  allocate( flatn(q_l1:q_h1))

  allocate(   div(lo(1):hi(1)+1))
  allocate( pdivu(lo(1):hi(1)  ))
  allocate(    q1(flux_l1-1:flux_h1+1,NGDNV))

  dx = delta(1)

  ! Check if we have violated the CFL criterion.
  call compute_cfl(q, q_lo_3D, q_hi_3D, &
                   qaux, [qa_l1, 0, 0], [qa_h1, 0, 0], &
                   lo_3D, hi_3D, dt, dx_3D, courno)

  ! Compute flattening coefficient for slope calculations.
  if (first_order_hydro == 1) then
     flatn = ZERO

  else if (use_flattening == 1) then
     call uflaten([lo(1) - ngf, 0, 0], [hi(1) + ngf, 0, 0], &
                  q(:,QPRES), q(:,QU), q(:,QV), q(:,QW), &
                  flatn, [q_l1, 0, 0], [q_h1, 0, 0])
  else
     flatn = ONE
  endif

  call umeth1d(lo,hi,domlo,domhi, &
               q,flatn,q_l1,q_h1, &
               qaux,qa_l1,qa_h1, &
               srcQ,srQ_l1,srQ_h1, &
               lo(1),hi(1),dx,dt, &
               flux,flux_l1,flux_h1, &
               q1,flux_l1-1,flux_h1+1, &
               bcMask, bcMask_l1, bcMask_h1, &
               dloga,dloga_l1,dloga_h1)
  ! Define p*divu
  do i = lo(1), hi(1)
     pdivu(i) = HALF * &
          (q1(i+1,GDPRES) + q1(i,GDPRES))* &
          (q1(i+1,GDU)*area(i+1) - q1(i,GDU)*area(i)) / vol(i)
  end do

  ! Define divu on surroundingNodes(lo,hi)
  do i = lo(1), hi(1)+1
     div(i) = (q(i,QU) - q(i-1,QU)) / dx
  enddo


  ! Conservative update
  call consup(uin,uin_l1,uin_h1, &
              uout,uout_l1,uout_h1, &
              update,updt_l1,updt_h1, &
              q,q_l1,q_h1, &
              flux,flux_l1,flux_h1, &
              q1,flux_l1-1,flux_h1+1, &
              area,area_l1,area_h1, &
              vol , vol_l1, vol_h1, &
              div ,pdivu,lo,hi,dx,dt,mass_added_flux,E_added_flux, &
              xmom_added_flux,ymom_added_flux,zmom_added_flux, &
              mass_lost,xmom_lost,ymom_lost,zmom_lost, &
              eden_lost,xang_lost,yang_lost,zang_lost, &
              verbose)
  if (coord_type .gt. 0) then
     pradial(lo(1):hi(1)+1) = q1(lo(1):hi(1)+1,GDPRES)
  end if

  deallocate(flatn,div,pdivu,q1)

end subroutine pc_umdrv
