# tests/calculator.Tests.ps1
$toolFile = "calculator.ps1"
$path = Get-ChildItem -Path "$PSScriptRoot/../tools/$toolFile", "$PSScriptRoot/../more_tools/$toolFile" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName

# Mocking UI Draw-Box for testing
function Draw-Box { param($Lines, $Title, $Color) }

# Load the tool
if (-not $path) { throw "Tool $toolFile not found" }
. $path

describe "Comprehensive Calculator Tool Tests" {
    
    context "Basic Arithmetic" {
        it "should evaluate 2 + 2 = 4" {
            Invoke-CalculatorTool -expression "2 + 2" | should Match "OK: 2 \+ 2 = 4"
        }
        it "should evaluate (10 / 2) * 5 = 25" {
            Invoke-CalculatorTool -expression "(10 / 2) * 5" | should Match "OK: \(10 / 2\) \* 5 = 25"
        }
    }

    context "Constants and Radians Trig" {
        it "should handle pi and e" {
            Invoke-CalculatorTool -expression "pi" | should Match "3.14159265358979"
            Invoke-CalculatorTool -expression "e" | should Match "2.71828182845905"
        }
        it "should handle sin(pi/2) = 1" {
            Invoke-CalculatorTool -expression "sin(pi/2)" | should Match "OK: sin\(pi/2\) = 1"
        }
    }

    context "Degree Mode Trig" {
        it "should handle sind(30) = 0.5" {
            Invoke-CalculatorTool -expression "sind(30)" | should Match "OK: sind\(30\) = 0.5"
        }
        it "should handle cosd(60) = 0.5" {
            Invoke-CalculatorTool -expression "cosd(60)" | should Match "OK: cosd\(60\) = 0.5"
        }
        it "should handle asind(0.5) = 30" {
            Invoke-CalculatorTool -expression "asind(0.5)" | should Match "OK: asind\(0.5\) = 30"
        }
        it "should handle nested degree trig: sind(30)^2 + cosd(30)^2 = 1" {
            Invoke-CalculatorTool -expression "sind(30)^2 + cosd(30)^2" | should Match "OK: sind\(30\)\^2 \+ cosd\(30\)\^2 = 1"
        }
    }

    context "Powers and Roots" {
        it "should handle 2^3 = 8" {
            Invoke-CalculatorTool -expression "2^3" | should Match "OK: 2\^3 = 8"
        }
        it "should handle 1 * (299792458^2)" {
            Invoke-CalculatorTool -expression "1 * (299792458^2)" | should Match "8.98755178736818"
        }
        it "should handle (1+2)^2 = 9" {
            Invoke-CalculatorTool -expression "(1+2)^2" | should Match "OK: \(1\+2\)\^2 = 9"
        }
        it "should handle left-associative power chains: 2^3^2 = 64" {
            Invoke-CalculatorTool -expression "2^3^2" | should Match "OK: 2\^3\^2 = 64"
        }
        it "should handle sqrt(144) = 12" {
            Invoke-CalculatorTool -expression "sqrt(144)" | should Match "OK: sqrt\(144\) = 12"
        }
    }

    context "Logarithms and Functions" {
        it "should handle log10(100) = 2" {
            Invoke-CalculatorTool -expression "log10(100)" | should Match "OK: log10\(100\) = 2"
        }
        it "should handle ln(e) = 1" {
            Invoke-CalculatorTool -expression "ln(e)" | should Match "OK: ln\(e\) = 1"
        }
        it "should handle arbitrary base log: log(8, 2) = 3" {
            Invoke-CalculatorTool -expression "log(8, 2)" | should Match "OK: log\(8, 2\) = 3"
        }
        it "should handle factorial: fact(5) = 120" {
            Invoke-CalculatorTool -expression "fact(5)" | should Match "OK: fact\(5\) = 120"
        }
    }

    context "Nesting and Parentheses" {
        it "should handle (1+(2+3))^2 = 36" {
            Invoke-CalculatorTool -expression "(1+(2+3))^2" | should Match "OK: \(1\+\(2\+3\)\)\^2 = 36"
        }
    }

    context "Error Handling" {
        it "should block invalid characters (security)" {
            Invoke-CalculatorTool -expression "Get-Process" | should Match "ERROR: expression contains unsupported elements: getprocess"
        }
        it "should return error on null result" {
            # Since safety check blocks empty strings and semicolons, we test with null input
            Invoke-CalculatorTool -expression "" | should Match "ERROR: expression cannot be empty."
        }
    }
}
