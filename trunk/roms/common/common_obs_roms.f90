MODULE common_obs_roms
!=======================================================================
!
! [PURPOSE:] Observational procedures
!
! [HISTORY:]
!   01/23/2009 Takemasa MIYOSHI  created
!   02/03/2009 Takemasa MIYOSHI  modified for ROMS
!
!=======================================================================
!$USE OMP_LIB
  USE common
  USE common_mpi
  USE common_obs
  USE common_roms
  USE common_mpi_roms
  USE common_letkf

  IMPLICIT NONE
  PUBLIC

  INTEGER,PARAMETER :: nslots=1 ! number of time slots for 4D-LETKF
  INTEGER,PARAMETER :: nbslot=1 ! basetime slot
!  REAL(r_size),PARAMETER :: sigma_obs=400.0d3
  REAL(r_size),PARAMETER :: sigma_obs=5.0d0 ! grids
  REAL(r_size),PARAMETER :: sigma_obsv=50.0d0 ! meters
  REAL(r_size),PARAMETER :: sigma_obst=3.0d0 ! slots
  REAL(r_size),SAVE :: dist_zero
  REAL(r_size),SAVE :: dist_zerov
  REAL(r_size),ALLOCATABLE,SAVE :: obselm(:)
  REAL(r_size),ALLOCATABLE,SAVE :: obslon(:)
  REAL(r_size),ALLOCATABLE,SAVE :: obslat(:)
  REAL(r_size),ALLOCATABLE,SAVE :: obslev(:)
  REAL(r_size),ALLOCATABLE,SAVE :: obsdat(:)
  REAL(r_size),ALLOCATABLE,SAVE :: obserr(:)
  REAL(r_size),ALLOCATABLE,SAVE :: obsi(:)
  REAL(r_size),ALLOCATABLE,SAVE :: obsj(:)
!  REAL(r_size),ALLOCATABLE,SAVE :: obsk(:)
  REAL(r_size),ALLOCATABLE,SAVE :: obsdep(:)
  REAL(r_size),ALLOCATABLE,SAVE :: obshdxf(:,:)
  INTEGER,SAVE :: nobsgrd(nlon,nlat)

CONTAINS
!-----------------------------------------------------------------------
! Initialize
!-----------------------------------------------------------------------
SUBROUTINE set_common_obs_roms
  IMPLICIT NONE
  REAL(r_size) :: v3d(nlon,nlat,nlev,nv3d)
  REAL(r_size) :: v2d(nlon,nlat,nv2d)
  REAL(r_size),PARAMETER :: gross_error=10.0d0
  REAL(r_size) :: dz,tg,qg
  REAL(r_size) :: dlon1,dlon2,dlon,dlat
  REAL(r_size),ALLOCATABLE :: wk2d(:,:)
  INTEGER,ALLOCATABLE :: iwk2d(:,:)
  REAL(r_size),ALLOCATABLE :: tmpelm(:)
  REAL(r_size),ALLOCATABLE :: tmplon(:)
  REAL(r_size),ALLOCATABLE :: tmplat(:)
  REAL(r_size),ALLOCATABLE :: tmplev(:)
  REAL(r_size),ALLOCATABLE :: tmpdat(:)
  REAL(r_size),ALLOCATABLE :: tmperr(:)
  REAL(r_size),ALLOCATABLE :: tmpi(:)
  REAL(r_size),ALLOCATABLE :: tmpj(:)
!  REAL(r_size),ALLOCATABLE :: tmpk(:)
  REAL(r_size),ALLOCATABLE :: tmpdep(:)
  REAL(r_size),ALLOCATABLE :: tmphdxf(:,:)
  INTEGER,ALLOCATABLE :: tmpqc0(:,:)
  INTEGER,ALLOCATABLE :: tmpqc(:)
  REAL(r_size),ALLOCATABLE :: tmp2elm(:)
  REAL(r_size),ALLOCATABLE :: tmp2lon(:)
  REAL(r_size),ALLOCATABLE :: tmp2lat(:)
  REAL(r_size),ALLOCATABLE :: tmp2lev(:)
  REAL(r_size),ALLOCATABLE :: tmp2dat(:)
  REAL(r_size),ALLOCATABLE :: tmp2err(:)
  REAL(r_size),ALLOCATABLE :: tmp2i(:)
  REAL(r_size),ALLOCATABLE :: tmp2j(:)
!  REAL(r_size),ALLOCATABLE :: tmp2k(:)
  REAL(r_size),ALLOCATABLE :: tmp2dep(:)
  REAL(r_size),ALLOCATABLE :: tmp2hdxf(:,:)
  INTEGER :: nobslots(nslots)
  INTEGER :: n,i,j,ierr,islot,nn,l,im
  INTEGER :: nj(0:nlat-1)
  INTEGER :: njs(1:nlat-1)
  CHARACTER(9) :: obsfile='obsTT.dat'
  CHARACTER(10) :: guesfile='gsTTNNN.nc'

  WRITE(6,'(A)') 'Hello from set_common_obs_roms'

  dist_zero = sigma_obs * SQRT(10.0d0/3.0d0) * 2.0d0
  dist_zerov = sigma_obsv * SQRT(10.0d0/3.0d0) * 2.0d0

  DO islot=1,nslots
    WRITE(obsfile(4:5),'(I2.2)') islot
    CALL get_nobs_mpi(obsfile,nobslots(islot))
  END DO
  nobs = SUM(nobslots)
  WRITE(6,'(I10,A)') nobs,' TOTAL OBSERVATIONS INPUT'
!
! INITIALIZE GLOBAL VARIABLES
!
  ALLOCATE( tmpelm(nobs) )
  ALLOCATE( tmplon(nobs) )
  ALLOCATE( tmplat(nobs) )
  ALLOCATE( tmplev(nobs) )
  ALLOCATE( tmpdat(nobs) )
  ALLOCATE( tmperr(nobs) )
  ALLOCATE( tmpi(nobs) )
  ALLOCATE( tmpj(nobs) )
!  ALLOCATE( tmpk(nobs) )
  ALLOCATE( tmpdep(nobs) )
  ALLOCATE( tmphdxf(nobs,nbv) )
  ALLOCATE( tmpqc0(nobs,nbv) )
  ALLOCATE( tmpqc(nobs) )
  tmpqc0 = 0
  tmphdxf = 0.0d0
!
! LOOP of timeslots
!
  nn=0
  timeslots: DO islot=1,nslots
    IF(nobslots(islot) == 0) CYCLE
    WRITE(obsfile(4:5),'(I2.2)') islot
    CALL read_obs_mpi(obsfile,nobslots(islot),&
      & tmpelm(nn+1:nn+nobslots(islot)),tmpi(nn+1:nn+nobslots(islot)),&
      & tmpj(nn+1:nn+nobslots(islot)),tmplev(nn+1:nn+nobslots(islot)),&
      & tmpdat(nn+1:nn+nobslots(islot)),tmperr(nn+1:nn+nobslots(islot)) )
    l=0
    DO
      im = myrank+1 + nprocs * l
      IF(im > nbv) EXIT
      WRITE(guesfile(3:7),'(I2.2,I3.3)') islot,im
      WRITE(6,'(A,I3.3,2A)') 'MYRANK ',myrank,' is reading a file ',guesfile
      CALL read_grd(guesfile,v3d,v2d)
!$OMP PARALLEL DO SCHEDULE(DYNAMIC) PRIVATE(n)
      DO n=1,nobslots(islot)
        tmplon(nn+n) = lon(NINT(tmpi(nn+n)),NINT(tmpj(nn+n)))
        tmplat(nn+n) = lat(NINT(tmpi(nn+n)),NINT(tmpj(nn+n)))
        !
        ! observational operator
        !
        CALL Trans_XtoY(tmpelm(nn+n),&
          & tmpi(nn+n),tmpj(nn+n),tmplev(nn+n),v3d,v2d,tmphdxf(nn+n,im))
        tmpqc0(nn+n,im) = 1
      END DO
!$OMP END PARALLEL DO
      l = l+1
    END DO
    nn = nn + nobslots(islot)
  END DO timeslots

  CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
  ALLOCATE(wk2d(nobs,nbv))
  wk2d = tmphdxf
  CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
  CALL MPI_ALLREDUCE(wk2d,tmphdxf,nobs*nbv,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,ierr)
  DEALLOCATE(wk2d)
  ALLOCATE(iwk2d(nobs,nbv))
  iwk2d = tmpqc0
  CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
  CALL MPI_ALLREDUCE(iwk2d,tmpqc0,nobs*nbv,MPI_INTEGER,MPI_MAX,MPI_COMM_WORLD,ierr)
  DEALLOCATE(iwk2d)

!$OMP PARALLEL DO SCHEDULE(DYNAMIC) PRIVATE(n,i)
  DO n=1,nobs
    tmpqc(n) = MINVAL(tmpqc0(n,:))
    IF(tmpqc(n) /= 1) CYCLE
    tmpdep(n) = tmphdxf(n,1)
    DO i=2,nbv
      tmpdep(n) = tmpdep(n) + tmphdxf(n,i)
    END DO
    tmpdep(n) = tmpdep(n) / REAL(nbv,r_size)
    DO i=1,nbv
      tmphdxf(n,i) = tmphdxf(n,i) - tmpdep(n) ! Hdx
    END DO
    tmpdep(n) = tmpdat(n) - tmpdep(n) ! y-Hx
    IF(ABS(tmpdep(n)) > gross_error*tmperr(n)) THEN !gross error
      tmpqc(n) = 0
    END IF
  END DO
!$OMP END PARALLEL DO
  DEALLOCATE(tmpqc0)

  WRITE(6,'(I10,A)') SUM(tmpqc),' OBSERVATIONS TO BE ASSIMILATED'

  CALL monit_dep(nobs,tmpelm,tmpdep,tmpqc)
!
! temporal observation localization
!
  nn = 0
  DO islot=1,nslots
    tmperr(nn+1:nn+nobslots(islot)) = tmperr(nn+1:nn+nobslots(islot)) &
      & * exp(0.25d0 * (REAL(islot-nbslot,r_size) / sigma_obst)**2)
    nn = nn + nobslots(islot)
  END DO
!
! SELECT OBS IN THE NODE
!
  nn = 0
  DO n=1,nobs
    IF(tmpqc(n) /= 1) CYCLE
!    IF(tmplat(n) < MINVAL(lat1) .OR. MAXVAL(lat1) < tmplat(n)) THEN
!      dlat = MIN( ABS(MINVAL(lat1)-tmplat(n)),ABS(MAXVAL(lat1)-tmplat(n)) )
!      IF(dlat > dlat_zero) CYCLE
!    END IF
!    IF(tmplon(n) < MINVAL(lon1) .OR. MAXVAL(lon1) < tmplon(n)) THEN
!      dlon1 = ABS(MINVAL(lon1) - tmplon(n))
!      dlon1 = MIN(dlon1,360.0d0-dlon1)
!      dlon2 = ABS(MAXVAL(lon1) - tmplon(n))
!      dlon2 = MIN(dlon2,360.0d0-dlon2)
!      dlon =  MIN(dlon1,dlon2) &
!         & * pi*re*COS(tmplat(n)*pi/180.d0)/180.0d0
!      IF(dlon > dist_zero) CYCLE
!    END IF
    nn = nn+1
    tmpelm(nn) = tmpelm(n)
    tmplon(nn) = tmplon(n)
    tmplat(nn) = tmplat(n)
    tmplev(nn) = tmplev(n)
    tmpdat(nn) = tmpdat(n)
    tmperr(nn) = tmperr(n)
    tmpi(nn) = tmpi(n)
    tmpj(nn) = tmpj(n)
!    tmpk(nn) = tmpk(n)
    tmpdep(nn) = tmpdep(n)
    tmphdxf(nn,:) = tmphdxf(n,:)
    tmpqc(nn) = tmpqc(n)
  END DO
  nobs = nn
  WRITE(6,'(I10,A,I3.3)') nobs,' OBSERVATIONS TO BE ASSIMILATED IN MYRANK ',myrank
!
! SORT
!
  ALLOCATE( tmp2elm(nobs) )
  ALLOCATE( tmp2lon(nobs) )
  ALLOCATE( tmp2lat(nobs) )
  ALLOCATE( tmp2lev(nobs) )
  ALLOCATE( tmp2dat(nobs) )
  ALLOCATE( tmp2err(nobs) )
  ALLOCATE( tmp2i(nobs) )
  ALLOCATE( tmp2j(nobs) )
!  ALLOCATE( tmp2k(nobs) )
  ALLOCATE( tmp2dep(nobs) )
  ALLOCATE( tmp2hdxf(nobs,nbv) )
  ALLOCATE( obselm(nobs) )
  ALLOCATE( obslon(nobs) )
  ALLOCATE( obslat(nobs) )
  ALLOCATE( obslev(nobs) )
  ALLOCATE( obsdat(nobs) )
  ALLOCATE( obserr(nobs) )
  ALLOCATE( obsi(nobs) )
  ALLOCATE( obsj(nobs) )
!  ALLOCATE( obsk(nobs) )
  ALLOCATE( obsdep(nobs) )
  ALLOCATE( obshdxf(nobs,nbv) )
  nobsgrd = 0
  nj = 0
!$OMP PARALLEL PRIVATE(i,j,n,nn)
!$OMP DO SCHEDULE(DYNAMIC)
  DO j=1,nlat-1
    DO n=1,nobs
      IF(tmpj(n) < j .OR. j+1 <= tmpj(n)) CYCLE
      nj(j) = nj(j) + 1
    END DO
  END DO
!$OMP END DO
!$OMP DO SCHEDULE(DYNAMIC)
  DO j=1,nlat-1
    njs(j) = SUM(nj(0:j-1))
  END DO
!$OMP END DO
!$OMP DO SCHEDULE(DYNAMIC)
  DO j=1,nlat-1
    nn = 0
    DO n=1,nobs
      IF(tmpj(n) < j .OR. j+1 <= tmpj(n)) CYCLE
      nn = nn + 1
      tmp2elm(njs(j)+nn) = tmpelm(n)
      tmp2lon(njs(j)+nn) = tmplon(n)
      tmp2lat(njs(j)+nn) = tmplat(n)
      tmp2lev(njs(j)+nn) = tmplev(n)
      tmp2dat(njs(j)+nn) = tmpdat(n)
      tmp2err(njs(j)+nn) = tmperr(n)
      tmp2i(njs(j)+nn) = tmpi(n)
      tmp2j(njs(j)+nn) = tmpj(n)
!      tmp2k(njs(j)+nn) = tmpk(n)
      tmp2dep(njs(j)+nn) = tmpdep(n)
      tmp2hdxf(njs(j)+nn,:) = tmphdxf(n,:)
    END DO
  END DO
!$OMP END DO
!$OMP DO SCHEDULE(DYNAMIC)
  DO j=1,nlat-1
    IF(nj(j) == 0) THEN
      nobsgrd(:,j) = njs(j)
      CYCLE
    END IF
    nn = 0
    DO i=1,nlon
      DO n=njs(j)+1,njs(j)+nj(j)
        IF(tmp2i(n) < i .OR. i+1 <= tmp2i(n)) CYCLE
        nn = nn + 1
        obselm(njs(j)+nn) = tmp2elm(n)
        obslon(njs(j)+nn) = tmp2lon(n)
        obslat(njs(j)+nn) = tmp2lat(n)
        obslev(njs(j)+nn) = tmp2lev(n)
        obsdat(njs(j)+nn) = tmp2dat(n)
        obserr(njs(j)+nn) = tmp2err(n)
        obsi(njs(j)+nn) = tmp2i(n)
        obsj(njs(j)+nn) = tmp2j(n)
!        obsk(njs(j)+nn) = tmp2k(n)
        obsdep(njs(j)+nn) = tmp2dep(n)
        obshdxf(njs(j)+nn,:) = tmp2hdxf(n,:)
      END DO
      nobsgrd(i,j) = njs(j) + nn
    END DO
    IF(nn /= nj(j)) THEN
!$OMP CRITICAL
      WRITE(6,'(A,2I)') 'OBS DATA SORT ERROR: ',nn,nj(j)
      WRITE(6,'(F6.2,A,F6.2)') j,'< J <',j+1
      WRITE(6,'(F6.2,A,F6.2)') MINVAL(tmp2j(njs(j)+1:njs(j)+nj(j))),'< OBSJ <',MAXVAL(tmp2j(njs(j)+1:njs(j)+nj(j)))
!$OMP END CRITICAL
    END IF
  END DO
!$OMP END DO
!$OMP END PARALLEL
  DEALLOCATE( tmp2elm )
  DEALLOCATE( tmp2lon )
  DEALLOCATE( tmp2lat )
  DEALLOCATE( tmp2lev )
  DEALLOCATE( tmp2dat )
  DEALLOCATE( tmp2err )
  DEALLOCATE( tmp2i )
  DEALLOCATE( tmp2j )
!  DEALLOCATE( tmp2k )
  DEALLOCATE( tmp2dep )
  DEALLOCATE( tmp2hdxf )
  DEALLOCATE( tmpelm )
  DEALLOCATE( tmplon )
  DEALLOCATE( tmplat )
  DEALLOCATE( tmplev )
  DEALLOCATE( tmpdat )
  DEALLOCATE( tmperr )
  DEALLOCATE( tmpi )
  DEALLOCATE( tmpj )
!  DEALLOCATE( tmpk )
  DEALLOCATE( tmpdep )
  DEALLOCATE( tmphdxf )
  DEALLOCATE( tmpqc )

  RETURN
END SUBROUTINE set_common_obs_roms
!-----------------------------------------------------------------------
! Transformation from model variables to an observation
!-----------------------------------------------------------------------
SUBROUTINE Trans_XtoY(elm,ri,rj,rlev,v3d,v2d,yobs)
  IMPLICIT NONE
  REAL(r_size),INTENT(IN) :: elm
  REAL(r_size),INTENT(IN) :: ri,rj,rlev
  REAL(r_size),INTENT(IN) :: v3d(nlon,nlat,nlev,nv3d)
  REAL(r_size),INTENT(IN) :: v2d(nlon,nlat,nv2d)
  REAL(r_size),INTENT(OUT) :: yobs
  REAL(r_size) :: wk1(1),wk2(1),depth(nlev)
  INTEGER :: k

  SELECT CASE (NINT(elm))
  CASE(id_u_obs) ! U
    yobs = v3d(NINT(ri),NINT(rj),nlev,iv3d_u) ! only surface
  CASE(id_v_obs) ! V
    yobs = v3d(NINT(ri),NINT(rj),nlev,iv3d_v) ! only surface
  CASE(id_t_obs) ! T
    wk1(1) = rlev
    CALL calc_depth(v2d(NINT(ri),NINT(rj),iv2d_z),phi0(NINT(ri),NINT(rj)),depth)
    CALL com_interp_spline(nlev,depth,v3d(NINT(ri),NINT(rj),:,iv3d_t),1,wk1,wk2)
    yobs = wk2(1)
  CASE(id_s_obs) ! S
    wk1(1) = rlev
    CALL calc_depth(v2d(NINT(ri),NINT(rj),iv2d_z),phi0(NINT(ri),NINT(rj)),depth)
    CALL com_interp_spline(nlev,depth,v3d(NINT(ri),NINT(rj),:,iv3d_s),1,wk1,wk2)
    yobs = wk2(1)
  CASE(id_z_obs) ! Z
    yobs = v2d(NINT(ri),NINT(rj),iv2d_z)
  END SELECT

  RETURN
END SUBROUTINE Trans_XtoY
!-----------------------------------------------------------------------
! Interpolation
!-----------------------------------------------------------------------
SUBROUTINE itpl_2d(var,ri,rj,var5)
  IMPLICIT NONE
  REAL(r_size),INTENT(IN) :: var(nlon,nlat)
  REAL(r_size),INTENT(IN) :: ri
  REAL(r_size),INTENT(IN) :: rj
  REAL(r_size),INTENT(OUT) :: var5
  REAL(r_size) :: ai,aj
  INTEGER :: i,j

  i = CEILING(ri)
  ai = ri - REAL(i-1,r_size)
  j = CEILING(rj)
  aj = rj - REAL(j-1,r_size)

  IF(i <= nlon) THEN
    var5 = var(i-1,j-1) * (1-ai) * (1-aj) &
       & + var(i  ,j-1) *    ai  * (1-aj) &
       & + var(i-1,j  ) * (1-ai) *    aj  &
       & + var(i  ,j  ) *    ai  *    aj
  ELSE
    var5 = var(i-1,j-1) * (1-ai) * (1-aj) &
       & + var(1  ,j-1) *    ai  * (1-aj) &
       & + var(i-1,j  ) * (1-ai) *    aj  &
       & + var(1  ,j  ) *    ai  *    aj
  END IF

  RETURN
END SUBROUTINE itpl_2d

SUBROUTINE itpl_3d(var,ri,rj,rk,var5)
  IMPLICIT NONE
  REAL(r_size),INTENT(IN) :: var(nlon,nlat,nlev)
  REAL(r_size),INTENT(IN) :: ri
  REAL(r_size),INTENT(IN) :: rj
  REAL(r_size),INTENT(IN) :: rk
  REAL(r_size),INTENT(OUT) :: var5
  REAL(r_size) :: ai,aj,ak
  INTEGER :: i,j,k

  i = CEILING(ri)
  ai = ri - REAL(i-1,r_size)
  j = CEILING(rj)
  aj = rj - REAL(j-1,r_size)
  k = CEILING(rk)
  ak = rk - REAL(k-1,r_size)

  IF(i <= nlon) THEN
    var5 = var(i-1,j-1,k-1) * (1-ai) * (1-aj) * (1-ak) &
       & + var(i  ,j-1,k-1) *    ai  * (1-aj) * (1-ak) &
       & + var(i-1,j  ,k-1) * (1-ai) *    aj  * (1-ak) &
       & + var(i  ,j  ,k-1) *    ai  *    aj  * (1-ak) &
       & + var(i-1,j-1,k  ) * (1-ai) * (1-aj) *    ak  &
       & + var(i  ,j-1,k  ) *    ai  * (1-aj) *    ak  &
       & + var(i-1,j  ,k  ) * (1-ai) *    aj  *    ak  &
       & + var(i  ,j  ,k  ) *    ai  *    aj  *    ak
  ELSE
    var5 = var(i-1,j-1,k-1) * (1-ai) * (1-aj) * (1-ak) &
       & + var(1  ,j-1,k-1) *    ai  * (1-aj) * (1-ak) &
       & + var(i-1,j  ,k-1) * (1-ai) *    aj  * (1-ak) &
       & + var(1  ,j  ,k-1) *    ai  *    aj  * (1-ak) &
       & + var(i-1,j-1,k  ) * (1-ai) * (1-aj) *    ak  &
       & + var(1  ,j-1,k  ) *    ai  * (1-aj) *    ak  &
       & + var(i-1,j  ,k  ) * (1-ai) *    aj  *    ak  &
       & + var(1  ,j  ,k  ) *    ai  *    aj  *    ak
  END IF

  RETURN
END SUBROUTINE itpl_3d
!-----------------------------------------------------------------------
! Monitor departure
!-----------------------------------------------------------------------
SUBROUTINE monit_dep(nn,elm,dep,qc)
  IMPLICIT NONE
  INTEGER,INTENT(IN) :: nn
  REAL(r_size),INTENT(IN) :: elm(nn)
  REAL(r_size),INTENT(IN) :: dep(nn)
  INTEGER,INTENT(IN) :: qc(nn)
  REAL(r_size) :: rmse_u,rmse_v,rmse_t,rmse_s,rmse_z
  REAL(r_size) :: bias_u,bias_v,bias_t,bias_s,bias_z
  INTEGER :: n,iu,iv,it,is,iz

  rmse_u = 0.0d0
  rmse_v = 0.0d0
  rmse_t = 0.0d0
  rmse_s = 0.0d0
  rmse_z = 0.0d0
  bias_u = 0.0d0
  bias_v = 0.0d0
  bias_t = 0.0d0
  bias_s = 0.0d0
  bias_z = 0.0d0
  iu = 0
  iv = 0
  it = 0
  is = 0
  iz = 0
  DO n=1,nn
    IF(qc(n) /= 1) CYCLE
    SELECT CASE(NINT(elm(n)))
    CASE(id_u_obs)
      rmse_u = rmse_u + dep(n)**2
      bias_u = bias_u + dep(n)
      iu = iu + 1
    CASE(id_v_obs)
      rmse_v = rmse_v + dep(n)**2
      bias_v = bias_v + dep(n)
      iv = iv + 1
    CASE(id_t_obs)
      rmse_t = rmse_t + dep(n)**2
      bias_t = bias_t + dep(n)
      it = it + 1
    CASE(id_s_obs)
      rmse_s = rmse_s + dep(n)**2
      bias_s = bias_s + dep(n)
      is = is + 1
    CASE(id_z_obs)
      rmse_z = rmse_z + dep(n)**2
      bias_z = bias_z + dep(n)
      iz = iz + 1
    END SELECT
  END DO
  IF(iu == 0) THEN
    rmse_u = undef
    bias_u = undef
  ELSE
    rmse_u = SQRT(rmse_u / REAL(iu,r_size))
    bias_u = bias_u / REAL(iu,r_size)
  END IF
  IF(iv == 0) THEN
    rmse_v = undef
    bias_v = undef
  ELSE
    rmse_v = SQRT(rmse_v / REAL(iv,r_size))
    bias_v = bias_v / REAL(iv,r_size)
  END IF
  IF(it == 0) THEN
    rmse_t = undef
    bias_t = undef
  ELSE
    rmse_t = SQRT(rmse_t / REAL(it,r_size))
    bias_t = bias_t / REAL(it,r_size)
  END IF
  IF(is == 0) THEN
    rmse_s = undef
    bias_s = undef
  ELSE
    rmse_s = SQRT(rmse_s / REAL(is,r_size))
    bias_s = bias_s / REAL(is,r_size)
  END IF
  IF(iz == 0) THEN
    rmse_z = undef
    bias_z = undef
  ELSE
    rmse_z = SQRT(rmse_z / REAL(iz,r_size))
    bias_z = bias_z / REAL(iz,r_size)
  END IF

  WRITE(6,'(A)') '== OBSERVATIONAL DEPARTURE ================================='
  WRITE(6,'(5A12)') 'U','V','T','SALT','ZETA'
  WRITE(6,'(5ES12.3)') bias_u,bias_v,bias_t,bias_s,bias_z
  WRITE(6,'(5ES12.3)') rmse_u,rmse_v,rmse_t,rmse_s,rmse_z
  WRITE(6,'(A)') '== NUMBER OF OBSERVATIONS TO BE ASSIMILATED ================'
  WRITE(6,'(5A12)') 'U','V','T','SALT','ZETA'
  WRITE(6,'(5I12)') iu,iv,it,is,iz
  WRITE(6,'(A)') '============================================================'

  RETURN
END SUBROUTINE monit_dep
!-----------------------------------------------------------------------
! Monitor departure from gues/anal mean
!-----------------------------------------------------------------------
SUBROUTINE monit_mean(file)
  CHARACTER(4),INTENT(IN) :: file
  REAL(r_size) :: v3d(nlon,nlat,nlev,nv3d)
  REAL(r_size) :: v2d(nlon,nlat,nv2d)
  REAL(r_size) :: elem
  REAL(r_size) :: bias_u,bias_v,bias_t,bias_s,bias_z
  REAL(r_size) :: rmse_u,rmse_v,rmse_t,rmse_s,rmse_z
  REAL(r_size) :: hdxf,dep,ri,rj,rk
  INTEGER :: n,iu,iv,it,is,iz
  CHARACTER(10) :: filename='filexxx.nc'

  rmse_u  = 0.0d0
  rmse_v  = 0.0d0
  rmse_t  = 0.0d0
  rmse_s = 0.0d0
  rmse_z = 0.0d0
  bias_u = 0.0d0
  bias_v = 0.0d0
  bias_t = 0.0d0
  bias_s = 0.0d0
  bias_z = 0.0d0
  iu = 0
  iv = 0
  it = 0
  is = 0
  iz = 0

  WRITE(filename(1:7),'(A4,A3)') file,'_me'
  CALL read_grd(filename,v3d,v2d)

  DO n=1,nobs
    CALL Trans_XtoY(obselm(n),obsi(n),obsj(n),obslev(n),v3d,v2d,hdxf)
    dep = obsdat(n) - hdxf
    SELECT CASE(NINT(obselm(n)))
    CASE(id_u_obs)
      rmse_u = rmse_u + dep**2
      bias_u = bias_u + dep
      iu = iu + 1
    CASE(id_v_obs)
      rmse_v = rmse_v + dep**2
      bias_v = bias_v + dep
      iv = iv + 1
    CASE(id_t_obs)
      rmse_t = rmse_t + dep**2
      bias_t = bias_t + dep
      it = it + 1
    CASE(id_s_obs)
      rmse_s = rmse_s + dep**2
      bias_s = bias_s + dep
      is = is + 1
    CASE(id_z_obs)
      rmse_z = rmse_z + dep**2
      bias_z = bias_z + dep
      iz = iz + 1
    END SELECT
  END DO

  IF(iu == 0) THEN
    rmse_u = undef
    bias_u = undef
  ELSE
    rmse_u = SQRT(rmse_u / REAL(iu,r_size))
    bias_u = bias_u / REAL(iu,r_size)
  END IF
  IF(iv == 0) THEN
    rmse_v = undef
    bias_v = undef
  ELSE
    rmse_v = SQRT(rmse_v / REAL(iv,r_size))
    bias_v = bias_v / REAL(iv,r_size)
  END IF
  IF(it == 0) THEN
    rmse_t = undef
    bias_t = undef
  ELSE
    rmse_t = SQRT(rmse_t / REAL(it,r_size))
    bias_t = bias_t / REAL(it,r_size)
  END IF
  IF(is == 0) THEN
    rmse_s = undef
    bias_s = undef
  ELSE
    rmse_s = SQRT(rmse_s / REAL(is,r_size))
    bias_s = bias_s / REAL(is,r_size)
  END IF
  IF(iz == 0) THEN
    rmse_z = undef
    bias_z = undef
  ELSE
    rmse_z = SQRT(rmse_z / REAL(iz,r_size))
    bias_z = bias_z / REAL(iz,r_size)
  END IF

  WRITE(6,'(3A)') '== PARTIAL OBSERVATIONAL DEPARTURE (',file,') =================='
  WRITE(6,'(5A12)') 'U','V','T','SALT','ZETA'
  WRITE(6,'(5ES12.3)') bias_u,bias_v,bias_t,bias_s,bias_z
  WRITE(6,'(5ES12.3)') rmse_u,rmse_v,rmse_t,rmse_s,rmse_z
  WRITE(6,'(A)') '== NUMBER OF OBSERVATIONS =================================='
  WRITE(6,'(5A12)') 'U','V','T','SALT','ZETA'
  WRITE(6,'(5I12)') iu,iv,it,is,iz
  WRITE(6,'(A)') '============================================================'

  RETURN
END SUBROUTINE monit_mean
!-----------------------------------------------------------------------
! Basic modules for observation input
!-----------------------------------------------------------------------
SUBROUTINE get_nobs_mpi(cfile,nn)
  IMPLICIT NONE
  CHARACTER(*),INTENT(IN) :: cfile
  INTEGER,INTENT(OUT) :: nn
  REAL(r_sngl) :: wk(6)
  INTEGER :: ios
  INTEGER :: iu,iv,it,is,iz
  INTEGER :: iunit
  LOGICAL :: ex

  nn = 0
  iu = 0
  iv = 0
  it = 0
  is = 0
  iz = 0
  iunit=91
  INQUIRE(FILE=cfile,EXIST=ex)
  IF(ex) THEN
    WRITE(6,'(A,I3.3,2A)') 'MYRANK ',myrank,' is accessing a file ',cfile
    OPEN(iunit,FILE=cfile,FORM='unformatted',ACCESS='sequential')
    DO
      READ(iunit,IOSTAT=ios) wk
      IF(ios /= 0) EXIT
      SELECT CASE(NINT(wk(1)))
      CASE(id_u_obs)
        iu = iu + 1
      CASE(id_v_obs)
        iv = iv + 1
      CASE(id_t_obs)
        it = it + 1
      CASE(id_s_obs)
        is = is + 1
      CASE(id_z_obs)
        iz = iz + 1
      END SELECT
      nn = nn + 1
    END DO
    WRITE(6,'(I10,A)') nn,' OBSERVATIONS INPUT'
    WRITE(6,'(A12,I10)') '          U:',iu
    WRITE(6,'(A12,I10)') '          V:',iv
    WRITE(6,'(A12,I10)') '          T:',it
    WRITE(6,'(A12,I10)') '       SALT:',is
    WRITE(6,'(A12,I10)') '       ZETA:',iz
    CLOSE(iunit)
  ELSE
    WRITE(6,'(2A)') cfile,' does not exist -- skipped'
  END IF

  RETURN
END SUBROUTINE get_nobs_mpi

SUBROUTINE read_obs_mpi(cfile,nn,elem,rlon,rlat,rlev,odat,oerr)
  IMPLICIT NONE
  CHARACTER(*),INTENT(IN) :: cfile
  INTEGER,INTENT(IN) :: nn
  REAL(r_size),INTENT(OUT) :: elem(nn) ! element number
  REAL(r_size),INTENT(OUT) :: rlon(nn) ! for the moment, ri
  REAL(r_size),INTENT(OUT) :: rlat(nn) ! for the moment, rj
  REAL(r_size),INTENT(OUT) :: rlev(nn) ! depth [meters]
  REAL(r_size),INTENT(OUT) :: odat(nn)
  REAL(r_size),INTENT(OUT) :: oerr(nn)
  REAL(r_sngl) :: wk(6)
  INTEGER :: n,iunit

  iunit=91
  WRITE(6,'(A,I3.3,2A)') 'MYRANK ',myrank,' is reading a file ',cfile
  OPEN(iunit,FILE=cfile,FORM='unformatted',ACCESS='sequential')
  DO n=1,nn
    READ(iunit) wk
    elem(n) = REAL(wk(1),r_size)
    rlon(n) = REAL(wk(2),r_size)
    rlat(n) = REAL(wk(3),r_size)
    rlev(n) = REAL(wk(4),r_size)
    odat(n) = REAL(wk(5),r_size)
    oerr(n) = REAL(wk(6),r_size)
  END DO
  CLOSE(iunit)

  RETURN
END SUBROUTINE read_obs_mpi

END MODULE common_obs_roms
