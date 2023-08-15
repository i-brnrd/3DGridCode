module inttau2
!! module contains routines related to the optical depth integration of a photon though a 3D grid.
   implicit none
   
   private
   public :: tauint1

CONTAINS

    subroutine tauint1(packet, grid)
    !! optical depth integration subroutine. The main workhorse of MCRT

        use gridset_mod,  only : cart_grid
        use iarray,       only : jmean, rhokap
        use photon_class, only : photon
        use random_mod,   only : ran2
        use vector_class, only : vector
        
        !> packet to move through the grid
        type(photon),    intent(inout) :: packet
        !> grid that the packet moves through
        type(cart_grid), intent(in)    :: grid

        ! intermediate position
        type(vector) :: pos
        real    :: tau, taurun, taucell, d, dcell
        integer :: celli, cellj, cellk
        logical :: dir(3)

        !change grid origin to lower left of the grid
        pos = packet%pos + grid%dim

        ! store current voxel in temp variables
        celli = packet%xcell
        cellj = packet%ycell
        cellk = packet%zcell

        ! setup to start integrating
        taurun = 0.
        d = 0.
        dir = (/.FALSE., .FALSE., .FALSE./)

        !sample optical distance
        tau = -log(ran2())
        do
            dir = (/.FALSE., .FALSE., .FALSE./)
            !get distance to nearest wall in direction dir
            dcell = wall_dist(packet, grid, celli, cellj, cellk, pos, dir)
            !calculate optical distnace to cell wall
            taucell = dcell * rhokap(celli,cellj,cellk)

            if(taurun + taucell < tau)then!still some tau to move
                taurun = taurun + taucell
                d = d + dcell

                jmean(celli, cellj, cellk) = jmean(celli, cellj, cellk) + dcell ! record fluence

                call update_pos(packet, grid, pos, celli, cellj, cellk, dcell, .TRUE., dir)
            else!moved full distance

                dcell = (tau - taurun) / rhokap(celli,cellj,cellk)
                d = d + dcell

                jmean(celli, cellj, cellk) = jmean(celli, cellj, cellk) + dcell ! record fluence

                call update_pos(packet, grid, pos, celli, cellj, cellk, dcell, .FALSE., dir)
                exit
            end if
            if(celli == -1 .or. cellj == -1 .or. cellk == -1)then
                packet%tflag = .true.
                exit
            end if
        end do
        
        ! move back to grid with origin at the centre
        packet%pos = pos - grid%dim
        packet%xcell = celli
        packet%ycell = cellj
        packet%zcell = cellk

    end subroutine tauint1
   
    real function wall_dist(packet, grid, celli, cellj, cellk, pos, dir)
    !!function that returns distant to nearest wall and which wall that is (x ,y or z)

        use gridset_mod,  only : cart_grid
        use photon_class, only : photon
        use vector_class, only : vector

        !> photon packet
        type(photon),    intent(inout) :: packet
        type(cart_grid), intent(in)    :: grid
        !> current position
        type(vector),    intent(inout) :: pos
        !> which wall will we hit
        logical,         intent(inout) :: dir(:)
        !> current voxel ID
        integer,         intent(inout) :: celli, cellj, cellk
        
        real :: dx, dy, dz

        ! get distance to a wall in the x direction
        if(packet%dir%x > 0.)then
            dx = (grid%xface(celli+1) - pos%x)/packet%dir%x
        elseif(packet%dir%x < 0.)then
            dx = (grid%xface(celli) - pos%x)/packet%dir%x
        elseif(packet%dir%x == 0.)then
            dx = 100000.
        end if

        ! get distance to a wall in the y direction
        if(packet%dir%y > 0.)then
            dy = (grid%yface(cellj+1) - pos%y)/packet%dir%y
        elseif(packet%dir%y < 0.)then
            dy = (grid%yface(cellj) - pos%y)/packet%dir%y
        elseif(packet%dir%y == 0.)then
            dy = 100000.
        end if

        ! get distance to a wall in the z direction
        if(packet%dir%z > 0.)then
            dz = (grid%zface(cellk+1) - pos%z)/packet%dir%z
        elseif(packet%dir%z < 0.)then
            dz = (grid%zface(cellk) - pos%z)/packet%dir%z
        elseif(packet%dir%z == 0.)then
            dz = 100000.
        end if

        !get closest wall
        wall_dist = min(dx, dy, dz)
        if(wall_dist < 0.)print'(A,7F9.5)','dcell < 0.0 warning! ',wall_dist,dx,dy,dz,packet%dir
        if(wall_dist == dx)dir=(/.TRUE., .FALSE., .FALSE./)
        if(wall_dist == dy)dir=(/.FALSE., .TRUE., .FALSE./)
        if(wall_dist == dz)dir=(/.FALSE., .FALSE., .TRUE./)
        if(.not.dir(1) .and. .not.dir(2) .and. .not.dir(3))print*,'Error in dir flag'
      
   end function wall_dist


    subroutine update_pos(packet, grid, pos, celli, cellj, cellk, dcell, wall_flag, dir)
    !! routine that upates postions of photon and calls fresnel routines if photon leaves current voxel

        use gridset_mod,  only : cart_grid
        use photon_class, only : photon
        use random_mod,   only : ran2
        use utils,        only : str
        use vector_class, only : vector

        type(photon),    intent(in)    :: packet      
        type(vector),    intent(inout) :: pos
        type(cart_grid), intent(in)    :: grid
        real,            intent(in)    :: dcell
        integer,         intent(inout) :: celli, cellj, cellk
        logical,         intent(in)    :: wall_flag, dir(:)

        ! if we hit a wall
        if(wall_flag)then
            ! in the x direction
            if(dir(1))then
                if(packet%dir%x > 0.)then
                    pos%x = grid%xface(celli+1) + grid%delta
                elseif(packet%dir%x < 0.)then
                    pos%x = grid%xface(celli) - grid%delta
                else
                    print*,'Error in x dir in update_pos', dir, packet%dir
                end if
                pos%y = pos%y + packet%dir%y*dcell 
                pos%z = pos%z + packet%dir%z*dcell
            ! y direction
            elseif(dir(2))then
                pos%x = pos%x + packet%dir%x*dcell
                if(packet%dir%y > 0.)then
                    pos%y = grid%yface(cellj+1) + grid%delta
                elseif(packet%dir%y < 0.)then
                    pos%y = grid%yface(cellj) - grid%delta
                else
                    print*,'Error in y dir in update_pos', dir, packet%dir
                end if
                pos%z = pos%z + packet%dir%z*dcell
            ! z direction
            elseif(dir(3))then
                pos%x = pos%x + packet%dir%x*dcell
                pos%y = pos%y + packet%dir%y*dcell 
                if(packet%dir%z > 0.)then
                    pos%z = grid%zface(cellk+1) + grid%delta
                elseif(packet%dir%z < 0.)then
                    pos%z = grid%zface(cellk) - grid%delta
                else
                    print*,'Error in z dir in update_pos', dir, packet%dir
                end if
            else
                print*,'Error in update_pos... '//str(dir)
                error stop 1
            end if
        else
            ! we dont hit a wall
            pos = pos + packet%dir * dcell
        end if

        if(wall_flag)then
            ! if we hit a wall, get current voxel
            call update_voxels(pos, grid, celli, cellj, cellk)
        end if
    end subroutine update_pos


    subroutine update_voxels(pos, grid, celli, cellj, cellk)
    !! updates the current voxel based upon position

        use gridset_mod,  only : cart_grid
        use vector_class, only : vector

        type(vector),    intent(in)    :: pos
        type(cart_grid), intent(in)    :: grid
        integer,         intent(inout) :: celli, cellj, cellk

        celli = find(pos%x, grid%xface) 
        cellj = find(pos%y, grid%yface)
        cellk = find(pos%z, grid%zface) 

    end subroutine update_voxels


    integer function find(val, a)
    !! searches for bracketing indicies for a value val in an array a

        real, intent(in) :: val, a(:)

        integer          :: n, lo, mid, hi

        n = size(a)
        lo = 0
        hi = n + 1

        if (val == a(1)) then
            find = 1
        else if (val == a(n)) then
            find = n-1
        else if((val > a(n)) .or. (val < a(1))) then
            find = -1
        else
            do
                if (hi-lo <= 1) exit
                mid = (hi+lo)/2
                if (val >= a(mid)) then
                    lo = mid
                else
                    hi = mid
                end if
            end do
            find = lo
        end if
    end function find
end module inttau2