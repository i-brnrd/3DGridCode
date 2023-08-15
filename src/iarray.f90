module iarray
!!  Contains all array variable names.

    implicit none
    !! stores the optical properties, i.e the total cross section \(\mu_t = \mu_s + \mu_a\)
    real, allocatable :: rhokap(:,:,:)
    !! stores the computed fluence
    real, allocatable :: jmean(:,:,:)
end module iarray
