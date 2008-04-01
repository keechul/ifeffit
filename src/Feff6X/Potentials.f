      subroutine Potentials(geomfile, potfile, ihole, 
     $     iexch, viexch, vrexch, rsexch, rmult, istat)

c 
c wrapper for Feff's Potentials Calculation
c     
      implicit none
      include 'dim.h'
      include 'const.h'
      character*(*)     geomfile, potfile
      double precision  viexch, vrexch, rsexch, rmult, rfac
      integer iexch, ihole, istat, j

      character*1024  line, tmpstr
      integer istrln, ilen, jlen, iflen, iret, i, ios, jmt
      integer mwords, nwords, ititle, jstat, ipot0, itmp,ifr, nph
      integer mrpts, iex, ier, npack
      logical debug
      parameter (mwords = 16)
      parameter (mrpts = 251)

      double precision  xnatph(0:nphx), vcoul(mrpts,0:nphx)
      double precision  dgc0(mrpts), dpc0(mrpts)
      double precision  rho(mrpts,0:nphx)
      double precision  xf, xmu, rs, rhoint, rnrmav, vint, edge
      double precision  em(nex)
      integer  imt(0:nphx)	!r mesh index just inside rmt
      integer  inrm(0:nphx)	!r mesh index just inside rnorman
      integer  iatph(0:nphx)	!given unique pot, which atom is model?
				!(0 if none specified for this unique pot)

      double precision vtot(mrpts,0:nphx) !overlapped total potential
      double precision rmt(0:nphx)	!muffin tin radius
      double precision rnrm(0:nphx)	!norman radius
      double precision edens(mrpts,0:nphx) !overlapped density*4*pi
      double precision vclap(mrpts,0:nphx) !overlapped coul pot
      double precision folp(0:nphx)	!overlap factor for rmt calculation

      integer  iphat(natx)	!given specific atom, which unique pot?
      double precision rat(3,natx)	!cartesian coords of specific atom

      double precision  ri(mrpts), vtotph(mrpts), rhoph(mrpts)

      complex*16 eref(nex)		!interstitial energy ref
      complex*16 ph(nex,ltot+1,0:nphx)	!phase shifts
      integer    lmax(0:nphx)    !number of ang mom levels

      integer ionin
      integer nr, ne,  nat, jat, ik0, iph, iprint
      character*6 potlbl(0:nphx)

      character*32 words(mwords), key
      character*256 title
      integer natoms, ipot(natx), iatnum(natx), izpot(0:nphx)
      double precision xat(natx), yat(natx), zat(natx)
      double precision gamach, etfin, et
      integer ii
      external istrln,ii
c
      iprint  = 0
      debug = istat.eq.1
      if (istrln(potfile) .le. 1) potfile = 'potentials.bin'

      do 25 i = 0, nphx
         iatph(i)  = 0
         imt(i)	   = 0
         iatph(i)  = 0
         xnatph(i) = 0.d0
         rmt(i)	 = 0.d0
         rnrm(i) = 0.d0
         folp(i) = 1.d0
         do 21 j = 1, mrpts
            edens(j,i) = 0.d0
            vtot(j,i) = 0.d0
            vclap(j,i) = 0.d0
 21      continue 
 25   continue 


c read XYZ geometry file
      natoms = natx
      print*, ' Potentials -> ReadXYZ ' 
      call ReadXYZ(geomfile, natx, nphx, iatnum, ipot, 
     $     xat, yat, zat, natoms, izpot, tmpstr, title, jstat)
      
      rfac = rmult / bohr
      do 60 i = 1, natoms
         xat(i) = xat(i) * rfac 
         yat(i) = yat(i) * rfac 
         zat(i) = zat(i) * rfac 
 60   continue

      if (jstat.ne.0) then 
         istat = 1
         return
      endif
c
      print*, ' Pot ReadXYZ done ', natoms, nphx
      nwords = mwords
      call strsplit(tmpstr,nwords,words,'$')
      nph = -1
      do i = 0, nphx
         if (izpot(i).ge.1) then 
            nph = i
            potlbl(i) = words(i+1)
            print*, '    POT', i, izpot(i), potlbl(i)
         endif
      enddo
c
c check which atom is Central Atom, set iatph, xnatph
      ipot0 = -1
      
      do 100 i = 1, natoms
         jat = ipot(i)
         if (jat .eq.0)  ipot0 = i
         if (iatph(jat) .eq. 0)  then
            iatph(jat) = i
         endif
         xnatph(jat) = 1 + xnatph(jat)
 100  continue 

      if (ipot0.eq.-1) then 
         istat = 1
         write(tmpstr,'(3a)')
     $        "Error: No central atom (IPOT=0) seen in '",
     $        geomfile(1:iflen), "'"
         call echo(tmpstr)
         return
      endif

c
c  get core-hole width
      call setgam (iatnum(ipot0), ihole, gamach)

c
c  get free atom potentials and densities
c     NB iwigner is needed in SUMAX, if changed here, change it there
      print*, 'number of potentials: ', nph
      do 20 iph = 0, nph
         itmp = 0
         if (iph .eq. 0)  itmp = ihole
         ionin = 0

         write(tmpstr,'(a,1x,i3)')
     $     'free atom potential and density for atom type', iph
         call echo(tmpstr)
         call atom(potlbl(iph), iph, izpot(iph), itmp, 
     $        ionin, vcoul(1,iph), rho(1,iph), dgc0, dpc0, et)
         
         if (iph .eq. 0)  etfin = et
ccc         print*,  iph, izpot(iph), itmp, et, rho(1,iph), rho(2,iph)
 20   continue
cc
cc  works to here
c
c     Overlap potentials and densitites
      print*, ' Overlap Potentials:: ', nph
      do 40  iph = 0, nph
         write(tmpstr,'(a,i3)') 
     1    'overlapped potential and density for unique potential', iph
         call echo(tmpstr)

cc         print*, '-> ovrlp ', iph, iatph(iph), izpot(iph), natoms
         call ovrlp (iph, iphat, xat, yat, zat, iatph, 
     1        izpot, natoms, rho, vcoul, edens, vclap, rnrm)
cc         print*, '<- ovrlp ', rho(1,iph), edens(1,iph), rnrm(iph)
   40 continue

c     Find muffin tin radii, add gsxc to potentials, and find
c     interstitial parameters
       call echo('    muffin tin radii and interstitial parameters')
       call istprm (nph, natoms, iphat, xat, yat, zat, iatph, xnatph,
     1             folp, edens,
     2             vclap, vtot, imt, inrm, rmt, rnrm, rhoint,
     3             vint, rs, xf, xmu, rnrmav)

       print*, 'Potentials after istprm ', rnrmav, nph, xmu, vint

c     Initialize header routine and write misc.dat
c$$$      call sthead (nhead0, head0, lhead0, nph, iz, rmt, rnrm,
c$$$     1             ion, ifrph, ihole, iexch,
c$$$     2             vrexch, viexch, rsexch, gamach, xmu, xf, vint, rs,
c$$$     3             nhead, lhead, head)
c$$$      if (iprint .ge. 1)  then
c$$$         open (unit=1, file='misc.dat', status='unknown', iostat=ios)
c$$$         call chopen (ios, 'misc.dat', 'potph')
c$$$         call wthead(1)
c$$$         close (unit=1)
c$$$      endif
c$$$
c$$$      if (iprint .ge. 2)  then
c$$$         call wpot (nph, edens, ifrph, imt, inrm,
c$$$     1              rho, vclap, vcoul, vtot)
c$$$      endif

c     Phase shift calculation
c     Make energy mesh and position grid

      edge = xmu - vrexch
      print*, 'Potentials, -> phmesh ', nph, edge, mrpts
      call phmesh (mrpts, nex, iprint, edge, vint, vrexch,
     1             imt, edens, nph,   ri, ne, em, ik0)

c     Cross section calculation, use phase mesh for now
c     remove xanes calculation in feff6l

      print*, 'Potentials, after phmesh ', nph
      do 160  iph = 0, nph
         write(tmpstr,'(a,i3)')
     $        'phase shifts for unique potential', iph
         call echo(tmpstr)
c        fix up variable for phase
         jmt = ii(rmt(iph))
         do 152  j = 1, jmt
            vtotph(j) = vtot(j,iph)
            rhoph(j)  = edens(j,iph)/(4*pi)
 152     continue
         do 154  j = jmt+1, mrpts
            vtotph(j) = vint
            rhoph(j) = rhoint/(4*pi)
 154     continue

         nr = mrpts
         print*, ' -> phase ', iph, nr,  ne,  edge, lmax(iph)

         call phase (iph, nr, ri, ne, em, edge,
     1               iexch, rmt(iph), xmu, viexch, rsexch, gamach,
     2               vtotph, rhoph, eref, ph(1,1,iph), lmax(iph))
 160  continue

c     Write out phases for genfmt
c     May need stuff for use with headers only
c$$$      open (unit=1, file='phase.bin', access='sequential',
c$$$     1      form='unformatted', status='unknown', iostat=ios)
c$$$      call chopen (ios, 'phase.bin', 'potph')
c$$$      write(1) nhead
c$$$      do 62  i = 1, nhead
c$$$         write(1) head(i)
c$$$         write(1) lhead(i)
c$$$   62 continue
c$$$      write(1) ne, nph, ihole, rnrmav, xmu, edge, ik0
c$$$      write(1) (em(ie),ie=1,ne)
c$$$      write(1) (eref(ie),ie=1,ne)
c$$$      do 80  iph = 0, nph
c$$$         write(1) lmax(iph), iz(ifrph(iph))
c$$$         write(1) potlbl(iph)
c$$$         do 70  ie = 1, ne
c$$$            write(1)  (ph(ie,ll,iph), ll=1,lmax(iph)+1)
c$$$   70    continue
c$$$   80 continue
c$$$      close (unit=1)

      call openfl(1, potfile,  'unknown', iex, ier)
      if ((ier.lt.0).or.(iex.lt.0)) then
          call echo(' *** Error: cannot open Potentials.bin')
          return
       end if
       npack = 8
       write(1,'(a,i3)') '#:FEFF6X POT File: npad = ', npack

       write(1, '(a,i15)') '#% ne    ', ne
       write(1, '(a,i15)') '#% nph   ', nph
       write(1, '(a,i15)') '#% ihole ', ihole
       write(1, '(a,i15)') '#% ik0   ', ik0
       write(1, '(a,g20.14)') '#% rnrmav ', rnrmav
       write(1, '(a,g20.14)') '#% xmu  ', xmu
       write(1, '(a,g20.14)') '#% edge ', edge



       close(1)
c     
c done!
      print*, 'Potentials done.  ', potfile(1:istrln(potfile))
      print*, '   Edge: ', ihole, ipot0, iatnum(ipot0), gamach
      print*, '   Exchange: ', iexch, vrexch, viexch, rsexch

      print*, '# ne, nph, ihole, rnrmav, xmu, edge, ik0 '
      print*,  ne, nph, ihole, rnrmav, xmu, edge, ik0 
      do iph = 0, nph
         print*, 'iph, lbl,iz,lmax=',
     $        iph, potlbl(iph), izpot(iph), lmax(iph)
      enddo

       close(1)
         
      return 
      end
