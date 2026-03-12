# Contributing

Here's a precise guide on what you should do to contribute code changes:

1. Open Staging (TODO: add link)
2. **File &gt; Publish As** to your individual developer experience. (Make sure you don't have it open, and that there's nothing there that is needed.)
3. Open your individual developer experience in Roblox Studio.
4. Update dependencies: `aftman install` and `wally install` (because dependencies may have been added/updated!)
5. Start syncing Rojo: `rojo serve` (or use the Rojo VS Code extension)
6. Create a new branch: base it on `main` using the `name/feature` naming convention, e.g. `ozzy/trampoline`.
7. Do programming work: commit changes incrementally to your branch. Optional: use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/#summary), e.g. "feat: Add Foobar component"
8. Optional: rebase your changes to keep a clean commit history, e.g. squash typo commits into the commit they are fixing, adjust commit messages
9. Push your changes to GitHub: `git push`
10. Submit a new Pull Request on GitHub: make it against `main` and describe your changes in plain English. See also: [Writing good CL descriptions](https://google.github.io/eng-practices/review/developer/cl-descriptions.html)
11. Add reviewers: add Artemis at minimum, and other engineers who have a stake in the changes you're proposing, e.g. if you're adding to their feature
12. Complete code review: once approved, leave the PR be! Tip: You can always continue work in a separate branch, basing your changes on existing branches, ideally those with already-approved or already-merged pull requests.
