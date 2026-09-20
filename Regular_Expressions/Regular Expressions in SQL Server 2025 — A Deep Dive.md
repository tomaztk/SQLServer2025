# Regular Expressions in SQL Server 2025 — A Deep Dive
**Level 400**

---

## Session Outline

1. Setup & demo data
2. The seven REGEXP functions — syntax and examples
3. REGEXP vs LIKE vs PATINDEX vs CLR — comparisons
4. Patternc omplexity classes
  - Literal search
  - simple character classes
  - alternation
  - Achnored vs. un-Anchored
  - unicode  matching
  - back-references
5. Backgracking / ReDoS
	- how does perf. degrade as input length grows?
	- what input length does the engine time out
	- does engine impose backtracking limit?
6. Engine Algorithm benchmarks - NFA vs. DFA vs. compiled
7. Operation Type benchmarks
 - Match / test	Does the patern match? (boolean)
 - Search / find	Where does it match? (position)
 - Extract / capture	What did it capture? (groups)
 - Replace	Substitute matches — allocation cost matters
 - Split	Tokenize on a delimiter pattern
 - Global / all matches	Find every match in a long string
8. Real-world use cases and benckmarks guidanes
9. Table design and indexing
10. Famous death-traps with RegEx    :(){:|:&};:
