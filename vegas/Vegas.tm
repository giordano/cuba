:Evaluate: BeginPackage["Vegas`"]

:Evaluate: Vegas::usage = "Vegas[f, {x, xmin, xmax}..] computes a numerical approximation to the integral of the real scalar or vector function f.
	The output is a list with entries of the form {integral, error, chi-square probability} for each component of the integrand."

:Evaluate: NStart::usage = "NStart is an option of Vegas.
	It specifies the number of integrand evaluations per iteration to start with."

:Evaluate: NIncrease::usage = "NIncrease is an option of Vegas.
	It specifies the increase in the number of integrand evaluations per iteration."

:Evaluate: GridNo::usage = "GridNo is an option of Vegas.
	Vegas maintains an internal table in which it can memorize up to 10 grids, to be used on subsequent integrations.
	A GridNo between 1 and 10 selects the slot in this internal table.
	For other values the grid is initialized from scratch and discarded at the end of the integration."

:Evaluate: State::usage = "State is an option of Vegas.
	It specifies a file in which the internal state is stored after each iteration and from which it can be restored on a subsequent run.
	The state file is removed once the prescribed accuracy has been reached."

:Evaluate: System`MinPoints::usage = "MinPoints is an option of Vegas.
	It specifies the minimum number of points to sample."

:Evaluate: System`Final::usage = "Final is an option of Vegas.
	It can take the values Last or All which determine whether only the last (largest) or all of the samples collected on a subregion over the iterations contribute to the final result."

:Evaluate: Begin["`Private`"]

:Begin:
:Function: Vegas
:Pattern: MLVegas[ndim_, ncomp_, epsrel_, epsabs_, flags_, mineval_, maxeval_,
  nstart_, nincrease_, gridno_, state_]
:Arguments: {ndim, ncomp, epsrel, epsabs, flags, mineval, maxeval,
  nstart, nincrease, gridno, state}
:ArgumentTypes: {Integer, Integer, Real, Real, Integer, Integer, Integer,
  Integer, Integer, Integer, String}
:ReturnType: Manual
:End:

:Evaluate: Attributes[Vegas] = {HoldFirst}

:Evaluate: Options[Vegas] = {PrecisionGoal -> 3, AccuracyGoal -> 12,
	MinPoints -> 0, MaxPoints -> 50000, NStart -> 1000, NIncrease -> 500,
	GridNo -> 0, State -> "", Verbose -> 1, Final -> All, Compiled -> True}

:Evaluate: Vegas[f_, v:{_, _, _}.., opt___Rule] :=
	Block[ {ff = HoldForm[f], ndim = Length[{v}],
	vars, lower, range, jac, tmp, defs, integrand, tags, rel, abs,
	mineval, maxeval, nstart, nincrease, gridno, verbose, final},
	  Message[Vegas::optx, #, Vegas]&/@
	    Complement[First/@ {opt}, tags = First/@ Options[Vegas]];
	  {rel, abs, mineval, maxeval, nstart, nincrease, gridno, state,
	    verbose, final, compiled} =
	    tags /. {opt} /. Options[Vegas];
	  {vars, lower, range} = Transpose[{v}];
	  jac = Simplify[Times@@ (range -= lower)];
	  tmp = Take[tmpvars, ndim];
	  defs = Simplify[lower + range tmp];
	  Block[{Set}, define[compiled, tmp, vars, Thread[vars = defs], jac]];
	  integrand = fun[f];
	  MLVegas[ndim, ncomp[f], 10.^-rel, 10.^-abs,
	    Min[Max[verbose, 0], 3] +
	      If[final === Last, 4, 0],
	    mineval, maxeval, nstart, nincrease, gridno, state]
	]

:Evaluate: tmpvars = Table[Unique["t"], {40}]

:Evaluate: Attributes[ncomp] = Attributes[fun] = {HoldAll}

:Evaluate: ncomp[f_List] := Length[f]

:Evaluate: _ncomp = 1

:Evaluate: define[True, tmp_, vars_, {defs__}, jac_] :=
	fun[f_] := Compile[tmp, Block[vars, defs; check[vars, Chop[f jac]//N]]]

:Evaluate: define[False, tmp_, vars_, {defs__}, jac_] :=
	fun[f_] := Function[tmp, Block[vars, defs; check[vars, Chop[f jac]//N]]]

:Evaluate: check[_, f_Real] = {f}

:Evaluate: check[_, f:{__Real}] = f

:Evaluate: check[x_, _] := (Message[Vegas::badsample, ff, x]; {})

:Evaluate: sample[x_] :=
	Check[Apply[integrand, Partition[x, ndim], 1]//Flatten, {}]

:Evaluate: Vegas::badsample = "`` is not a real-valued function at ``."

:Evaluate: Vegas::baddim = "Can integrate only in dimensions `` through ``."

:Evaluate: Vegas::accuracy =
	"Desired accuracy was not reached within `` function evaluations."

:Evaluate: Vegas::success = "Needed `` function evaluations."

:Evaluate: End[]

:Evaluate: EndPackage[]


/*
	Vegas.tm
		Vegas Monte-Carlo integration
		by Thomas Hahn
		last modified 18 Nov 04
*/


#include <setjmp.h>
#include "mathlink.h"
#include "util.c"

jmp_buf abort_;

/*********************************************************************/

static void Status(MLCONST char *msg, cint n1, cint n2)
{
  MLPutFunction(stdlink, "CompoundExpression", 2);
  MLPutFunction(stdlink, "Message", 3);
  MLPutFunction(stdlink, "MessageName", 2);
  MLPutSymbol(stdlink, "Vegas");
  MLPutString(stdlink, msg);
  MLPutInteger(stdlink, n1);
  MLPutInteger(stdlink, n2);
}

/*********************************************************************/

static void Print(MLCONST char *s)
{
  int pkt;

  MLPutFunction(stdlink, "EvaluatePacket", 1);
  MLPutFunction(stdlink, "Print", 1);
  MLPutString(stdlink, s);
  MLEndPacket(stdlink);

  do {
    pkt = MLNextPacket(stdlink);
    MLNewPacket(stdlink);
  } while( pkt != RETURNPKT );
}

/*********************************************************************/

static void DoSample(ccount n, real *x, real *f)
{
  int pkt;
  real *mma_f;
  long mma_n;

  if( MLAbort ) goto abort;

  MLPutFunction(stdlink, "EvaluatePacket", 1);
  MLPutFunction(stdlink, "Vegas`Private`sample", 1);
  MLPutRealList(stdlink, x, n*ndim_);
  MLEndPacket(stdlink);

  while( (pkt = MLNextPacket(stdlink)) && (pkt != RETURNPKT) )
    MLNewPacket(stdlink);

  if( !MLGetRealList(stdlink, &mma_f, &mma_n) ) {
    MLClearError(stdlink);
    MLNewPacket(stdlink);
abort:
    MLPutFunction(stdlink, "Abort", 0);
    longjmp(abort_, 1);
  }

  if( mma_n != n*ncomp_ ) {
    MLDisownRealList(stdlink, mma_f, mma_n);
    MLPutSymbol(stdlink, "$Failed");
    longjmp(abort_, 1);
  }

  Copy(f, mma_f, n*ncomp_);
  MLDisownRealList(stdlink, mma_f, mma_n);

  neval_ += n;
}

/*********************************************************************/

#include "common.c"

void Vegas(ccount ndim, ccount ncomp,
  creal epsrel, creal epsabs, cint flags, ccount mineval, ccount maxeval,
  ccount nstart, ccount nincrease, ccount gridno, const char *state)
{
  ndim_ = ndim;
  ncomp_ = ncomp;

  if( ndim < MINDIM || ndim > MAXDIM ) {
    Status("baddim", MINDIM, MAXDIM);
    MLPutSymbol(stdlink, "$Failed");
  }
  else {
    real integral[NCOMP], error[NCOMP], prob[NCOMP];
    count comp;
    int fail;

    neval_ = 0;
    vegasgridno_ = gridno;
    strncpy(vegasstate_, state, STATESIZE - 1);
    vegasstate_[STATESIZE - 1] = 0;

    fail = Integrate(epsrel, epsabs,
      flags, mineval, maxeval, nstart, nincrease,
      integral, error, prob);

    Status(fail ? "accuracy" : "success", neval_, 0);

    MLPutFunction(stdlink, "List", ncomp);
    for( comp = 0; comp < ncomp; ++comp ) {
      real res[] = {integral[comp], error[comp], prob[comp]};
      MLPutRealList(stdlink, res, Elements(res));
    }
  }

  MLEndPacket(stdlink);
}

/*********************************************************************/

int main(int argc, char **argv)
{
  return MLMain(argc, argv);
}

