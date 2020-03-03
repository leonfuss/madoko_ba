/*---------------------------------------------------------------------------
  Copyright 2013-2015 Microsoft Corporation.

  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the file "license.txt" at the root of this distribution.
---------------------------------------------------------------------------*/

// Main Madoko driver: provides files etc. and calls madoko.markdown
module driver

import std/log
import std/regex
import std/path
import std/dict
import std/date
import std/string
import common
import options
import metadata
import madoko
import block    // for lineMap
import storage
import hilite
import texParser
import includes

public struct runners()

val standardTexStyles = ["ellipse.sty","options.sty","longbox.sty","longfbox.sty","madoko2.sty"]

public function processContent( inName : string, outName : string, content : string,
                          opts : commandOptions, firstTime : bool = False,
                          runners : runners,
                          continue : (output:string,inputName:string,outputName:string,options:options) -> io () ) : io ()
{
  val styleDir = opts.installDir + "/../styles"
  val searchDirs = [inName.dirname,outName.dirname,styleDir]
  val opts0  = if (inName.endsWith(".xmp.html") || inName.endsWith(".xmp"))
                then (opts.options)(xmp = True,full = opts.options.full.maybe(Just(False),Just)) else opts.options
  content.include(False, inName, outName, searchDirs, opts0) fun(icontent0,lmap) {
    // remove madoko comments
    val icontent = icontent0.removeMadokoComments
    // set up options

    val date   = now()
    val xopts  = opts0(lineMap=lmap,
                       metadata=opts0.metadata
                       + [("docname",inName.stemname),("filename",inName)]
                       + [("madoko-version",opts0.version)]
                       + [("date",date.isoLocalDate),("time",date.isoLocalTime.substr(0,5)),
                          ("year",date.year.show),("month",date.month.show2),("day",date.day.show2),
                          ("hours",date.hours.show2),("minutes",date.minutes.show2),("seconds",date.seconds.show2)] )

    val mopts = if (xopts.xmp)
                  then xopts.parseMeta( FmtHtml, icontent.normalizeSource.extractFirstXmp ).fst
                  else xopts.parseMeta( FmtHtml, icontent.normalizeSource ).fst  // get bibdata,bibstyle,mathimg

    // register languages for highlighting
    registerColorizers(mopts, searchDirs, icontent);

    // copy early since async latex may start for math
    if (mopts.copyStyles) {
      tryCopyTextFileFromNoSandboxTo( "madoko.css", styleDir, outName.dirname )

      val isTex2  = match(mopts.metadata.find( fun(md) { md.fst == "tex2" } )) {
                      Just(md) -> md.snd.toLower == "true"
                      _ -> False
                    }
      val files = if (isTex2)
                   then standardTexStyles
                   else ["css.sty", "madoko.sty"]
      files.foreach fun(fname) {
        tryCopyTextFileFromNoSandboxTo(fname, styleDir, outName.dirname )
      }
    }

    process( inName, outName, searchDirs, content, icontent, xopts, mopts, firstTime, runners)
      fun() {
        processContent(inName,outName,content,opts,False,runners,continue) // redo!
      }
      fun(html) {
        continue(html,inName,outName,mopts)
      }
  }
}

function extractFirstXmp( s : string ) : string {
  match (s.find(rxXmp)) {
    Nothing -> ""
    Just(cap) -> cap.groups[1]
  }
}
val rxXmp = regex(@"<xmp\b.*?>([\s\S]*?)</xmp>")

val rxCurDir = regex(@"^(\.)(?=[\\/])")

function process( inName : string, outName : string, searchDirs : list<string>,
                  content : string, icontent : string,
                  xopts : options, mopts : options, firstTime : bool, runners : runners,
                  redo : () -> io (),
                  continue : (string) -> io () ) : io ()
{
  function phaseHtml()
  {
    // markdown to html
    val (warns0,(_, (_,_fullOptions,_,_))) =
         withLogCompress("warning") {
          withLogCompress("aux") {
           markdown(icontent,xopts)
         }}

    // show warnings
    val warns = fixWarnings(warns0)
    if (warns != "") {
      log("stdout",warns)
      if (mopts.verbose >= 1) {
        print(warns)
      }
    }

    // generate tex
    val outTexName = outName.changeExt(".tex")
    val texRefers =
      if (!mopts.tex) then [] else {
        if (mopts.verbose >= 1) println("process: " + inName + " -> " + outTexName )
        val (texwarns, (texFiles, (texRefer, tex)))
              = withLog("texwarning", {
                  withLog("files", {
                    withLog("filesRefer", {
                     markdown(icontent,xopts,FmtTex).fst
                    })
                  })
                })
        if (texwarns != "") {
          log("stdout",texwarns)
          if (mopts.verbose>=1) {
            print(texwarns)
          }
        }
        if (!(tryWriteTextFile(outTexName,tex))) {
          mopts.printErr("error: unable to write: " + outTexName)
        }
        texFiles.split("\n").list + texRefer.split("\n").list
      }
    continue("")
  }

  phaseHtml()
}

// Fixup locations in warnings:
function fixWarnings(txt : string) : string {
  var location := "";
  val hist = mdict();
  val ls = txt.lines.list.map fun(line) {
    match(line.find(rxLocation)) {
      Nothing -> {
        match(line.find(rxWarning)) {
          Nothing   -> Just(line + "\n")
          Just(cap) -> {
            val count = hist[line].mbint
            hist[line] := count+1
            if (count == 4)
             then Just("warning: " + location + " ignoring from now on:" + line + "\n")
            elif (count > 4)
             then Nothing
             else Just(cap.groups[1] + location + cap.groups[2] + "\n")
          }
        }
      }
      Just(cap) -> {
        location := cap.groups[1] + ":"
        Nothing
      }
    }
  }
  ls.concatMaybe.join
}
val rxLocation = regex(@"^\s*location:(.*)",ignoreCase=True)
val rxWarning  = regex(@"^(\s*(?:error|warning):)(.*)",ignoreCase=True)

// Remove <!--madoko comments
function removeMadokoComments( txt : string ) : string {
  txt.replaceAll( rxMadokoComment, "\n$1\n")
}
val rxMadokoComment = regex(@"^<!--madoko[ \t\r]*\n([\s\S]*?)^-->[ \t\r]*\n", ignoreCase=True, multiline=True)

// Register colorizers
function registerColorizers( opts : options, searchDirs : list<string>, content : string ) : io ()
{
  val searchDirsEx = searchDirs.concat( fun(dir) { [dir,combine(dir,"lang")] } )
  val registered = mdict()
  val langs1 = opts.hilitelang.split(";").list
  val langs2 = content.findAll(regex(@"(?:^ *```+ *|\blanguage\s*[:=])([\w\-\/]+)\b",multiline=True)).list.map(fun(cap) { cap.groups[1].basename })
  val langs  = (langs1 + langs2).map(toLower)
  langs.foreach fun(lang) {
    match (registered[lang]) {
      Just -> ()
      Nothing -> {
        registered[lang] := True
        if (lang != "") {
          match( trySearchReadTextFile(lang,searchDirsEx,".json")) {
            Nothing -> {
              log("files", changeExt(lang,".json"))
              opts.printErr("warning: unable to read language definition: " + lang)
            }
            Just((_,definition)) -> {
              val langName = lang.basename.noext.toLower
              //trace("register language: " + langName + ":\n" + definition )
              registerLanguage(langName,definition)
            }
          }
        }
      }
    }
  }
}

public function outputName( inputName : string, options : commandOptions ) : string {
  val noextName = if (inputName.endsWith(".xmp.html")) then inputName.substr(0,inputName.length-9) else inputName.noext
  val outName = if (options.convertTex) then inputName + ".mdk" else noextName + ".html"
  if (options.outputDir=="")
   then outName
   else options.outputDir + "/" + outName.basename
}

function tryCopyTextFileFromNoSandboxTo( fname, srcDir, outDir ) {
  val inName = combine(srcDir,fname)
  val outName = combine(outDir,fname)
  catch {
    val txt = readTextFileNoSandbox( inName )
    tryWriteTextFile(outName,txt)
    ()
  }
  fun(exn) { () }
}


public function withLogCompress( name: string, action : () -> <ndet|e> a ) : <ndet|e> (string,a) {
  val (log,x) = withLog(name,action)
  (log.replaceAll(rxDataLinesPre,""), x)
}

val rxDataLinesPre = regex("(?:\r?\n%mdk-data-line=.*(?=\r?\n%mdk-data-line))+")
