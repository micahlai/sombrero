/** Resolve a raster I/O library for technical slicing and playback exports. */
import path from 'node:path';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
export function imageLibrary(name='sharp'){
  const directories=[process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES,...(process.env.NODE_REPL_NODE_MODULE_DIRS||'').split(path.delimiter),'/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules'];
  try{return require(name);}catch{}
  for(const directory of directories.filter(Boolean)){try{return require(path.join(directory,name));}catch{}}
  throw new Error(`Missing ${name}; install it locally or expose its module directory via NODE_REPL_NODE_MODULE_DIRS.`);
}
export const sharp=imageLibrary();
