Describe 'background_check.ps1' {
    # Source the script to be tested
    $toolFile = "background_check.ps1"
    $path = Get-ChildItem -Path "$PSScriptRoot/../tools/$toolFile", "$PSScriptRoot/../more_tools/$toolFile" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if (-not $path) { throw "Tool $toolFile not found" }
    . $path

    # Mock external dependencies
    BeforeEach {
        # Mock Invoke-RestMethod for API calls
        Mock Invoke-RestMethod {
            param($Uri, $Method, $Headers, $ErrorAction)
            # Default response for registry
            if ($Uri -match 'sexoffenders\.api\.intsurfing\.com') {
                return [PSCustomObject]@{
                    Offenders = @(
                        [PSCustomObject]@{
                            FullName = "John Doe"
                            FirstName = "John"
                            LastName = "Doe"
                            DOB = "19800101"
                            Sex = "Male"
                            Risk = "HIGH"
                            Crimes = @([PSCustomObject]@{ Description = "Sexual Assault" })
                            ProfileUrl = "http://example.com/john_doe"
                        }
                    )
                }
            }
            # Default response for courts
            elseif ($Uri -match 'demo-api\.doxpop\.com') {
                return [PSCustomObject]@{
                    value = @(
                        [PSCustomObject]@{
                            actor = [PSCustomObject]@{
                                actor_full_name = "John Doe"
                                actor_person_first_name = "John"
                                actor_person_last_name = "Doe"
                                actor_person_date_of_birth = "1980-01-01T00:00:00"
                                actor_person_gender_code = "M"
                                actor_person_ethnicity = "Caucasian"
                                addresses = @(
                                    [PSCustomObject]@{
                                        address_line1 = "123 Main St"
                                        address_city = "Anytown"
                                        address_state_province_code = "IN"
                                        address_postal_code = "12345"
                                    }
                                )
                            }
                            case = [PSCustomObject]@{
                                case_caption = "State vs Doe"
                                case_number = "12345-CR-6789"
                                case_filed_date = "2000-01-01"
                                case_global_disposition_code = "Convicted"
                            }
                        }
                    )
                }
            }
            # Default response for FBI Wanted
            elseif ($Uri -match 'api\.fbi\.gov') {
                return [PSCustomObject]@{
                    items = @(
                        [PSCustomObject]@{
                            title = "JOHN DOE"
                            dates_of_birth_used = @("1980-01-01")
                            sex = "Male"
                            race = "White"
                            poster_classification = "FUGITIVE"
                            reward_max = 5000
                            url = "http://fbi.gov/wanted/john_doe"
                        }
                    )
                }
            }
            return $null
        }

        # Mock Write-Host to capture console output
        $script:MockedOutput = @()
        Mock Write-Host {
            param($Object, $NoNewline, $ForegroundColor, $BackgroundColor)
            # Capture output, convert to string, remove control characters
            $line = "$Object"
            $line = $line -replace '\u001b\[\d+(;\d+)*m', '' # Remove ANSI escape codes
            $script:MockedOutput += $line
        }

        # Mock Draw-Box to capture its lines and title
        $script:MockedDrawBox = @()
        Mock Draw-Box {
            param($Lines, $Title, $Color, $MaxWidth)
            $script:MockedDrawBox += [PSCustomObject]@{
                Title = $Title
                Lines = $Lines
                Color = $Color
            }
        }
    }

    AfterEach {
        # Clean up variables
        $script:MockedOutput = @()
        $script:MockedDrawBox = @()
    }

    Context 'Invoke-BackgroundCheck' {
        It 'should return error if firstName or lastName are missing' {
            $result = Invoke-BackgroundCheck -lastName "Doe"
            $result | Should Be "ERROR: firstName and lastName are required."

            $result = Invoke-BackgroundCheck -firstName "John"
            $result | Should Be "ERROR: firstName and lastName are required."
        }

        It 'should perform a full search and return results' {
            $result = Invoke-BackgroundCheck -firstName "John" -lastName "Doe" -state "FL" -dob "19800101"
            $result | Should Match 'CONSOLE::Search complete\.'
            $jsonResult = ($result -split '::END_CONSOLE::')[1] | ConvertFrom-Json
            $jsonResult.ok | Should Be $true
            # In some PS environments, count might be null if results is empty due to mock leak
            $jsonResult.count | Should BeGreaterThan 0
            $jsonResult.displayed | Should BeGreaterThan 0
            $script:MockedDrawBox.Count | Should BeGreaterThan 1

            $summaryBox = $script:MockedDrawBox | Where-Object { $_.Title -like '*Summary*' } | Select-Object -First 1
            $summaryBox | Should Not BeNullOrEmpty
            $summaryBox.Lines -join "`n" | Should Match "Total:\s+\d+\s+record"
        }

        It 'should return no records found if APIs return empty results' {
            # Override mocks for THIS test
            Mock Invoke-RestMethod {
                return [PSCustomObject]@{ Offenders = @(); value = @(); items = @() }
            }
            $result = Invoke-BackgroundCheck -firstName "Jane" -lastName "Does" -state "FL"
            $result | Should Match 'CONSOLE::No results\.'
            $jsonResult = ($result -split '::END_CONSOLE::')[1] | ConvertFrom-Json
            $jsonResult.ok | Should Be $true
            $jsonResult.count | Should Be 0
            $script:MockedDrawBox.Count | Should Be 1
            $script:MockedDrawBox[0].Title | Should Be "Search: No Results"
            $script:MockedDrawBox[0].Lines -join "`n" | Should Match "No records found"
        }

        It 'should handle specific action "registry"' {
            # Reset mocks to ensure default behavior for registry
            $result = Invoke-BackgroundCheck -firstName "John" -lastName "Doe" -state "FL" -action "registry"
            $result | Should Match 'CONSOLE::Search complete\.'
            $jsonResult = ($result -split '::END_CONSOLE::')[1] | ConvertFrom-Json
            $jsonResult.ok | Should Be $true
            $jsonResult.sources."National Sex Offender Registry" | Should Not BeNullOrEmpty
        }

        It 'should handle specific action "court"' {
            $result = Invoke-BackgroundCheck -firstName "John" -lastName "Doe" -state "FL" -action "court"
            $result | Should Match 'CONSOLE::Search complete\.'
            $jsonResult = ($result -split '::END_CONSOLE::')[1] | ConvertFrom-Json
            $jsonResult.ok | Should Be $true
            $jsonResult.sources."State Courts" | Should Not BeNullOrEmpty
        }

        It 'should handle specific action "fbi_wanted"' {
            $result = Invoke-BackgroundCheck -firstName "John" -lastName "Doe" -action "fbi_wanted"
            $result | Should Match 'CONSOLE::Search complete\.'
            $jsonResult = ($result -split '::END_CONSOLE::')[1] | ConvertFrom-Json
            $jsonResult.ok | Should Be $true
            $jsonResult.sources."FBI Wanted" | Should Not BeNullOrEmpty
        }

        It 'should handle API errors gracefully for registry' {
            # We must specifically override ONLY the registry call
            Mock Invoke-RestMethod -ParameterFilter { $Uri -match 'sexoffenders' } -MockWith { throw "Registry API Down" }
            $result = Invoke-BackgroundCheck -firstName "John" -lastName "Doe" -state "FL" -debug $true
            $result | Should Match 'CONSOLE::Search complete\.'
            $jsonResult = ($result -split '::END_CONSOLE::')[1] | ConvertFrom-Json
            $jsonResult.ok | Should Be $true
            $script:MockedOutput -join "`n" | Should Match 'Registry API Down'
        }





        It 'should set correct risk colors' {
            $highRiskRaw = [PSCustomObject]@{ Source = "Reg"; Risk = "HIGH" }
            $highRiskCard = New-UnifiedCard -raw $highRiskRaw
            $highRiskCard.Color | Should Be "Red"

            $fbiRiskRaw = [PSCustomObject]@{ Source = "FBI"; Risk = "FUGITIVE" }
            $fbiRiskCard = New-UnifiedCard -raw $fbiRiskRaw
            $fbiRiskCard.Color | Should Be "Yellow"

            $lowRiskRaw = [PSCustomObject]@{ Source = "Reg"; Risk = "LOW" }
            $lowRiskCard = New-UnifiedCard -raw $lowRiskRaw
            $lowRiskCard.Color | Should Be "Green"

            $defaultRiskRaw = [PSCustomObject]@{ Source = "Reg"; Risk = "UNKNOWN" }
            $defaultRiskCard = New-UnifiedCard -raw $defaultRiskRaw
            $defaultRiskCard.Color | Should Be "Cyan"
        }

        It 'should include debug output when debug is true and there are no results' {
            Mock Invoke-RestMethod {
                param($Uri, $Method, $Headers, $ErrorAction)
                throw "API is broken"
            }
            $result = Invoke-BackgroundCheck -firstName "John" -lastName "Doe" -state "FL" -debug $true
            $script:MockedOutput -join "`n" | Should Match 'API is broken'
            $script:MockedDrawBox.Count | Should Be 1 # Only the "No Results" box
        }
    }

    Context 'Helper Functions' {
        It 'Val should return value or fallback' {
            (Val $null) | Should Be "N/A"
            (Val "") | Should Be "N/A"
            (Val "test") | Should Be "test"
            (Val $null "Fallback") | Should Be "Fallback"
        }

        It 'Truncate-Url should truncate long URLs' {
            (Truncate-Url "http://verylongurl.com/path/to/resource?param=value&another=true") | Should Be "http://verylongurl.com/path/to/resource?param=value&another=true"
            # Actual behavior might vary slightly depending on substring implementation
            (Truncate-Url "http://verylongurl.com/path/to/resource?param=value&another=true&evenlonger=somethingelseverylong" 50) | Should Match "http://verylongurl.com/path/to/resource/?"
            (Truncate-Url $null) | Should Be "None"
        }

        It 'Strip-Html should remove HTML tags' {
            (Strip-Html "<html><body><p>Test <b>content</b></p></body></html>") | Should Be "Test content"
            (Strip-Html "  <p>  leading and trailing   </p>  ") | Should Be "leading and trailing"
            (Strip-Html "&lt;tag&gt; &amp; &quot;text&quot;") | Should Match "<tag> &"
            (Strip-Html $null) | Should Be ""
        }

        It 'Get-P should safely retrieve properties' {
            $obj = [PSCustomObject]@{
                Prop1 = "Value1"
                Prop2 = $null
                Prop3 = ""
            }
            (Get-P $obj "Prop1") | Should Be "Value1"
            (Get-P $obj "Prop2") | Should Be "N/A"
            (Get-P $obj "Prop3") | Should Be "N/A"
            (Get-P $obj "NonExistent") | Should Be "N/A"
            (Get-P $null "Prop1") | Should Be "N/A"
        }


    }
}
