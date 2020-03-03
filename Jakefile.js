#!/usr/bin/env node

//----------------------------------------------------------------------------
// Copyright 2013 Microsoft Corporation, Daan Leijen
//
// This is free software; you can redistribute it and/or modify it under the
// terms of the Apache License, Version 2.0. A copy of the License can be
// found in the file "license.txt" at the root of this distribution.
//----------------------------------------------------------------------------
var fs = require("fs");
var path = require("path");
var child = require("child_process");


//-----------------------------------------------------
// Configuration
//-----------------------------------------------------
var main       = "madoko";
var maincli    = "main";
var sourceDir  = "src";
var outputDir  = "lib";
var styleDir   = "styles";
var contribDir = "contrib";

// we compile madoko at this time with an older version of Koka.
// Check out Koka in a peer directory of Madoko; i.e. `.../dev/madoko` and `.../dev/koka-0.6`:
//
// > cd ..
// > git clone https://github.com/koka-lang/koka.git  koka-0.6
//
// Then set it to the older version:
//
// > cd koka-0.6
// > git checkout v0.6.1-dev   (or v0.6.x-dev)
// > npm install
//
// and build the release version:
//
// > jake compiler VARIANT=release

var kokaDir   = "../koka-0.6"
var libraryDir= path.join(kokaDir,"lib")
var kokaExe   = path.join(kokaDir,"out/release/koka-0.6.0-dev")
var testDir   = "test";

var kokaFlags = "-i" + sourceDir + " -i" + libraryDir + " " + (process.env.kokaFlags || "");
var kokaCmd = kokaExe + " " + kokaFlags + " -c -o" + outputDir + " --outname=" + main + " "


//-----------------------------------------------------
// Tasks: compilation
//-----------------------------------------------------
task("default",["madoko"]);

desc(["build madoko.",
      "  madoko[cs] # generate .NET binary."].join("\n"));
task("madoko", [], function(cs) {
  args = ""
  if (cs) {
    args = "--target=cs -o" + outputDir + "net"
  }
  if (!fileExist(outputDir)) {
    fs.mkdirSync(outputDir);
  }
  fixVersion();
  var cmd = kokaCmd + " -v " + args + " " + maincli;
  jake.logger.log("> " + cmd);
  jake.exec(cmd, {interactive: true}, function() {
    jake.cpR(path.join(sourceDir,"cli.js"), outputDir);
    ["monarch/monarch.js"].forEach( function(contrib) {
      jake.cpR(path.join(contribDir,contrib), outputDir);
    });
    complete();
  })
},{async:true});

desc("interactive madoko.");
task("interactive", [], function(mainmod) {
  mainmod = mainmod || maincli
  var cmd = kokaCmd + " -e -p " + mainmod
  jake.logger.log("> " + cmd);
  jake.exec(cmd, {interactive: true}, function() { complete(); })
},{async:true});

desc("run 'npm install' to install prerequisites.");
task("config", [], function () {
  if (!fileExist("node_modules")) {
    var cmd = "npm install";
    jake.logger.log("> " + cmd);
    jake.exec(cmd + " 2>&1", {interactive: true}, function() { complete(); });
  }
  else {
    complete();
  }
},{async:true});

desc("install local styles");
task("copystyles", [], function() {
  // copy locales
  jake.mkdirP(path.join(styleDir,"locales"));
  var js = new jake.FileList().include(path.join(contribDir,"csl/locales/*.xml"));
  copyFiles(path.join(contribDir,"csl"),js.toArray(),styleDir);
  // copy CSL styles
  jake.mkdirP(path.join(styleDir,"csl"));
  var js = new jake.FileList().include(path.join(contribDir,"csl/csl/*.csl"));
  copyFiles(path.join(contribDir,"csl"),js.toArray(),styleDir);
});


//-----------------------------------------------------
// Tasks: clean
//-----------------------------------------------------
desc("remove all generated files.");
task("clean", function() {
  jake.logger.log("remove all generated files");
  jake.rmRf(outputDir);
  jake.rmRf(outputDir + "net");
  jake.rmRf(outputDir + "doc");
  jake.rmRf("doc/out");
  jake.rmRf("web/client/lib");
});


//-----------------------------------------------------
// Tasks: test
//-----------------------------------------------------
desc("run tests.\n  test[--extra]    # run tests for extensions.");
task("test", ["madoko"], function() {
  testFlags=(process.env.testFlags||"")
  args = Array.prototype.slice.call(arguments)
  testCmd = "node test " + testFlags + args.filter(function(s){ return (s.substr(0,2) == "--"); }).join(" ")
  jake.log("> " + testCmd)
  jake.exec(testCmd, {printStdout: true, printStderr: true})
});


//-----------------------------------------------------
// Tasks: help
//-----------------------------------------------------
var usageInfo = [
  "usage: jake target[options]",
  "  <options>        are target specific, like bench[--quick].",
  ""].join("\n");

function showHelp() {
  jake.logger.log(usageInfo);
  jake.showAllTaskDescriptions(jake.program.opts.tasks);
  process.exit();
}

desc("show this information");
task("help",[],function() {
  showHelp();
});
task("?",["help"]);

if (process.argv.indexOf("-?") >= 0 || process.argv.indexOf("?") >= 0) {
  showHelp();
}
else if (jake.program.opts.tasks) {
  jake.logger.log(usageInfo);
};


//-----------------------------------------------------
// Get the version from the package.json file
//-----------------------------------------------------
function getVersion() {
  var content = fs.readFileSync("package.json",{encoding: "utf8"});
  if (content) {
    var matches = content.match(/"version"\s*\:\s*"([\w\.\-]+)"/);
    if (matches && matches.length >= 2) {
      return matches[1];
    }
  }
  return "<unknown>"
}


function fixVersion(fname) {
  fname = fname || path.join(sourceDir,"version.kk");

  var version = getVersion();
  var content1 = fs.readFileSync(fname,{encoding: "utf8"});
  if (content1) {
    var content2 = content1.replace(/^(public\s*val\s*version\s*=\s*)"[^"\n]*"/m, "$1\"" + version + "\"")
                           .replace(/(<span\s+id="version">)[^<\n]*(?=<\/span>)/, "$1" + version)
    if (content1 !== content2) {
      jake.logger.log("updating version string in '" + fname + "' to '" + version + "'")
      fs.writeFileSync(fname,content2,{encoding: "utf8"});
    }
  }
}

function fileExist(fileName) {
  var stats = null;
  try {
    stats = fs.statSync(fileName);
  }
  catch(e) {};
  return (stats != null);
}

// copyFiles 'files' to 'destdir' where the files in destdir are named relative to 'rootdir'
// i.e. copyFiles('A',['A/B/c.txt'],'D')  creates 'D/B/c.txt'
function copyFiles(rootdir,files,destdir) {
  rootdir = rootdir || "";
  rootdir = rootdir.replace(/\\/g, "/");
  jake.mkdirP(destdir);
  files.forEach(function(filename) {
    // make relative
    var destname = path.join(destdir,(rootdir && filename.lastIndexOf(rootdir,0)===0 ? filename.substr(rootdir.length) : filename));
    var logfilename = (filename.length > 30 ? "..." + filename.substr(filename.length-30) : filename);
    var logdestname = (destname.length > 30 ? "..." + destname.substr(destname.length-30) : destname);
    //jake.logger.log("cp -r " + logfilename + " " + logdestname);
    jake.cpR(filename,path.dirname(destname));
  })
}
