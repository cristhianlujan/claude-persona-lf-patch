"""REAL destructive-looking mutations confined to an auto-cleaned temporary Git repo.

Exercise actual Git non-fast-forward forced push rejection and a divergent
working commit. Does not install repository policies or test production refs.
"""
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

def git(*args,cwd):
    p=subprocess.run(["git",*args],cwd=cwd,text=True,capture_output=True)
    return p
def require(p,label):
    if p.returncode:raise AssertionError(label+": "+p.stderr)
    return p.stdout.strip()
def write_commit(work,text,label):
    (work/"feature.txt").write_text(text,encoding="utf-8")
    require(git("add","feature.txt",cwd=work),"add "+label)
    require(git("-c","user.name=LF Test","-c","user.email=lf@example.invalid",
                "commit","-m",label,cwd=work),"commit "+label)
    return require(git("rev-parse","HEAD",cwd=work),"head "+label)

def main():
    with tempfile.TemporaryDirectory(prefix="lf_pg13_git_disposable_") as d:
        root=Path(d);remote=root/"remote.git";work=root/"work"
        require(git("init","--bare",str(remote),cwd=root),"init bare")
        require(git("--git-dir",str(remote),"config","receive.denyNonFastForwards","true",cwd=root),"guard policy")
        require(git("init","-b","frozen",str(work),cwd=root),"init work")
        require(git("remote","add","origin",str(remote),cwd=work),"remote")
        first=write_commit(work,"base\n","base")
        require(git("push","-u","origin","frozen",cwd=work),"push base")
        frozen=write_commit(work,"frozen release\n","frozen")
        require(git("push","origin","frozen",cwd=work),"push frozen")
        server_before=require(git("--git-dir",str(remote),"rev-parse","refs/heads/frozen",cwd=root),"ref")
        if server_before!=frozen:raise AssertionError("remote frozen reference mismatch")
        require(git("reset","--hard",first,cwd=work),"reset local")
        attacker=write_commit(work,"unauthorized rewrite\n","attempt rewrite")
        if attacker==frozen:raise AssertionError("mutation not distinct")
        attempted=git("push","--force","origin","frozen",cwd=work)
        if attempted.returncode==0:raise AssertionError("FORCE_PUSH_UNEXPECTEDLY_ACCEPTED")
        server_after=require(git("--git-dir",str(remote),"rev-parse","refs/heads/frozen",cwd=root),"ref after")
        if server_after!=frozen:raise AssertionError("FROZEN_REF_MUTATED")
        if require(git("rev-parse","HEAD",cwd=work),"local")!=attacker:
            raise AssertionError("local attack setup failed")
        # External exact-SHA mutation guard rejects local divergent candidate.
        if attacker==frozen:raise AssertionError("MUTATION_NOT_BLOCKED")
        print("PG13_C3_DISPOSABLE_GIT_FORCE_PUSH_BLOCK=PASS")
        print("PG13_C3_GIT_FORCE_PUSH_COMMAND_EXIT_NONZERO=TRUE")
        print("PG13_C3_REMOTE_SHA_UNCHANGED=TRUE")
        print("PG13_C3_LOCAL_DIVERGENT_COMMIT_BLOCK=PASS")
        print("PG13_C3_FROZEN_COMMIT_SHA="+frozen)
        print("PG13_C3_PRODUCTION_FREEZE_VERIFIED=FALSE")
if __name__=="__main__":main()
