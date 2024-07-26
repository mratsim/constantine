# Named Algebraic Objects

This folder holds named fields and named curves configuration and precomputed constants.


⚠️ For Twisted Edwards curves
  The formula are complete only if d is not a square, otherwise
  they must be modified to handle the identity/neutral element with conditional moves.

Sage script to check with Bandersnatch constants for example
  r = Integer('0x1cfb69d4ca675f520cce760202687600ff8f87007419047174fd06b52876e7e1')
  d = Integer('0x6389c12633c267cbc66e3bf86be3b6d8cb66677177e54f92b369f2f5188d58e7')
  GF(r)(d).nth_root(2, all=True)
