#!/bin/zsh
# Run the same synchronous XCTest methods with lightweight assertions when CLT lacks XCTest.
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache"
swift build --disable-sandbox --cache-path "$PWD/.build/package-cache"
bin_dir="$(swift build --disable-sandbox --cache-path "$PWD/.build/package-cache" --show-bin-path)"
python3 - "$bin_dir" <<'PY'
import pathlib, re, sys
out=pathlib.Path(sys.argv[1])/'checks.swift'
preamble='''import Foundation
import PetCore
import PetAssets
class XCTestCase {}
func XCTFail(_ message:String = "Failed", file:StaticString = #filePath, line:UInt = #line) { fatalError("\\(file):\\(line): \\(message)") }
func XCTAssertTrue(_ value:Bool, file:StaticString = #filePath, line:UInt = #line) { if !value { XCTFail("Expected true",file:file,line:line) } }
func XCTAssertFalse(_ value:Bool, file:StaticString = #filePath, line:UInt = #line) { XCTAssertTrue(!value,file:file,line:line) }
func XCTAssertEqual<T:Equatable>(_ a:T,_ b:T,file:StaticString = #filePath,line:UInt = #line) { if a != b { XCTFail("\\(a) != \\(b)",file:file,line:line) } }
func XCTAssertEqual(_ a:Double,_ b:Double,accuracy:Double,file:StaticString = #filePath,line:UInt = #line) { XCTAssertTrue(abs(a-b)<=accuracy,file:file,line:line) }
func XCTAssertGreaterThanOrEqual<T:Comparable>(_ a:T,_ b:T) { XCTAssertTrue(a>=b) }
func XCTAssertLessThanOrEqual<T:Comparable>(_ a:T,_ b:T) { XCTAssertTrue(a<=b) }
func XCTAssertNil<T>(_ a:T?) { XCTAssertTrue(a == nil) }
func XCTAssertNotNil<T>(_ a:T?) { XCTAssertTrue(a != nil) }
func XCTUnwrap<T>(_ a:T?) throws -> T { guard let a else { XCTFail("Expected non-nil"); throw NSError(domain:"Check",code:1) }; return a }
'''
calls=[]
for file in sorted(pathlib.Path('Tests/PetCoreTests').glob('*.swift')):
    text=file.read_text()
    name=re.search(r'final class (\w+): XCTestCase',text)[1]
    for method in re.finditer(r'func (test\w+)\(\)( throws)?',text):
        call=('try ' if method[2] else '')+f'{name}().{method[1]}()'
        calls.append(call+f'; print("PASS {method[1]}")')
    preamble+='\n'+text.replace('import XCTest','').replace('@testable import PetCore','import PetCore')
out.write_text(preamble+'\n'+'\n'.join(calls)+f'\nprint("Passed {len(calls)} checks")\n')
PY
swiftc -I "$bin_dir/Modules" "$bin_dir/checks.swift" "$bin_dir"/PetCore.build/*.swift.o "$bin_dir"/PetAssets.build/*.swift.o -o "$bin_dir/duck-checks"
"$bin_dir/duck-checks"
