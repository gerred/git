#!/bin/sh

test_description='compare & swap push force/delete safety'

. ./test-lib.sh

setup_srcdst_basic () {
	rm -fr src dst &&
	git clone --no-local . src &&
	git clone --no-local src dst &&
	(
		cd src && git checkout HEAD^0
	)
}

test_expect_success setup '
	# create template repository
	test_commit A &&
	test_commit B &&
	test_commit C
'

test_expect_success 'push to update (protected)' '
	setup_srcdst_basic &&
	(
		cd dst &&
		test_commit D &&
		test_must_fail git push --force-with-lease=main:main origin main 2>err &&
		grep "stale info" err
	) &&
	git ls-remote . refs/heads/main >expect &&
	git ls-remote src refs/heads/main >actual &&
	test_cmp expect actual
'

test_expect_success 'push to update (protected, forced)' '
	setup_srcdst_basic &&
	(
		cd dst &&
		test_commit D &&
		git push --force --force-with-lease=main:main origin main 2>err &&
		grep "forced update" err
	) &&
	git ls-remote dst refs/heads/main >expect &&
	git ls-remote src refs/heads/main >actual &&
	test_cmp expect actual
'

test_expect_success 'push to update (protected, tracking)' '
	setup_srcdst_basic &&
	(
		cd src &&
		git checkout main &&
		test_commit D &&
		git checkout HEAD^0
	) &&
	git ls-remote src refs/heads/main >expect &&
	(
		cd dst &&
		test_commit E &&
		git ls-remote . refs/remotes/origin/main >expect &&
		test_must_fail git push --force-with-lease=main origin main &&
		git ls-remote . refs/remotes/origin/main >actual &&
		test_cmp expect actual
	) &&
	git ls-remote src refs/heads/main >actual &&
	test_cmp expect actual
'

test_expect_success 'push to update (protected, tracking, forced)' '
	setup_srcdst_basic &&
	(
		cd src &&
		git checkout main &&
		test_commit D &&
		git checkout HEAD^0
	) &&
	(
		cd dst &&
		test_commit E &&
		git ls-remote . refs/remotes/origin/main >expect &&
		git push --force --force-with-lease=main origin main
	) &&
	git ls-remote dst refs/heads/main >expect &&
	git ls-remote src refs/heads/main >actual &&
	test_cmp expect actual
'

test_expect_success 'push to update (allowed)' '
	setup_srcdst_basic &&
	(
		cd dst &&
		test_commit D &&
		git push --force-with-lease=main:main^ origin main
	) &&
	git ls-remote dst refs/heads/main >expect &&
	git ls-remote src refs/heads/main >actual &&
	test_cmp expect actual
'

test_expect_success 'push to update (allowed, tracking)' '
	setup_srcdst_basic &&
	(
		cd dst &&
		test_commit D &&
		git push --force-with-lease=main origin main 2>err &&
		! grep "forced update" err
	) &&
	git ls-remote dst refs/heads/main >expect &&
	git ls-remote src refs/heads/main >actual &&
	test_cmp expect actual
'

test_expect_success 'push to update (allowed even though no-ff)' '
	setup_srcdst_basic &&
	(
		cd dst &&
		git reset --hard HEAD^ &&
		test_commit D &&
		git push --force-with-lease=main origin main 2>err &&
		grep "forced update" err
	) &&
	git ls-remote dst refs/heads/main >expect &&
	git ls-remote src refs/heads/main >actual &&
	test_cmp expect actual
'

test_expect_success 'push to delete (protected)' '
	setup_srcdst_basic &&
	git ls-remote src refs/heads/main >expect &&
	(
		cd dst &&
		test_must_fail git push --force-with-lease=main:main^ origin :main
	) &&
	git ls-remote src refs/heads/main >actual &&
	test_cmp expect actual
'

test_expect_success 'push to delete (protected, forced)' '
	setup_srcdst_basic &&
	(
		cd dst &&
		git push --force --force-with-lease=main:main^ origin :main
	) &&
	git ls-remote src refs/heads/main >actual &&
	test_must_be_empty actual
'

test_expect_success 'push to delete (allowed)' '
	setup_srcdst_basic &&
	(
		cd dst &&
		git push --force-with-lease=main origin :main 2>err &&
		grep deleted err
	) &&
	git ls-remote src refs/heads/main >actual &&
	test_must_be_empty actual
'

test_expect_success 'cover everything with default force-with-lease (protected)' '
	setup_srcdst_basic &&
	(
		cd src &&
		git branch naster main^
	) &&
	git ls-remote src refs/heads/\* >expect &&
	(
		cd dst &&
		test_must_fail git push --force-with-lease origin main main:naster
	) &&
	git ls-remote src refs/heads/\* >actual &&
	test_cmp expect actual
'

test_expect_success 'cover everything with default force-with-lease (allowed)' '
	setup_srcdst_basic &&
	(
		cd src &&
		git branch naster main^
	) &&
	(
		cd dst &&
		git fetch &&
		git push --force-with-lease origin main main:naster
	) &&
	git ls-remote dst refs/heads/main |
	sed -e "s/main/naster/" >expect &&
	git ls-remote src refs/heads/naster >actual &&
	test_cmp expect actual
'

test_expect_success 'new branch covered by force-with-lease' '
	setup_srcdst_basic &&
	(
		cd dst &&
		git branch branch main &&
		git push --force-with-lease=branch origin branch
	) &&
	git ls-remote dst refs/heads/branch >expect &&
	git ls-remote src refs/heads/branch >actual &&
	test_cmp expect actual
'

test_expect_success 'new branch covered by force-with-lease (explicit)' '
	setup_srcdst_basic &&
	(
		cd dst &&
		git branch branch main &&
		git push --force-with-lease=branch: origin branch
	) &&
	git ls-remote dst refs/heads/branch >expect &&
	git ls-remote src refs/heads/branch >actual &&
	test_cmp expect actual
'

test_expect_success 'new branch already exists' '
	setup_srcdst_basic &&
	(
		cd src &&
		git checkout -b branch main &&
		test_commit F
	) &&
	(
		cd dst &&
		git branch branch main &&
		test_must_fail git push --force-with-lease=branch: origin branch
	)
'

test_expect_success 'background updates of REMOTE can be mitigated with a non-updated REMOTE-push' '
	rm -rf src dst &&
	git init --bare src.bare &&
	test_when_finished "rm -rf src.bare" &&
	git clone --no-local src.bare dst &&
	test_when_finished "rm -rf dst" &&
	(
		cd dst &&
		test_commit G &&
		git remote add origin-push ../src.bare &&
		git push origin-push main:main
	) &&
	git clone --no-local src.bare dst2 &&
	test_when_finished "rm -rf dst2" &&
	(
		cd dst2 &&
		test_commit H &&
		git push
	) &&
	(
		cd dst &&
		test_commit I &&
		git fetch origin &&
		test_must_fail git push --force-with-lease origin-push &&
		git fetch origin-push &&
		git push --force-with-lease origin-push
	)
'

test_done
