PRECISION  = DOUBLE
PROFILE    = FALSE
USE_EB     = FALSE
DEBUG      = FALSE

DIM        = 3

COMP	   = gcc

USE_MPI    = TRUE
USE_OMP    = FALSE

# define the location of the PELE top directory
PELE_HOME    := ../../..

# This sets the EOS directory in $(PELE_PHYSICS_HOME)/Eos
Eos_dir     := GammaLaw

# This sets the network directory in $(PELE_PHYSICS_HOME)/Reactions
Reactions_dir := Null

# This sets the transport directory in $(PELE_PHYSICS_HOME)/Transport
Transport_dir := Constant

Bpack   := ./Make.package
Blocs   := .

include ../Make.PeleC
