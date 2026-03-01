# tests/Splatting.Tests.ps1

Describe "Tool Parameter Splatting" {
    BeforeAll {
        function ConvertTo-Hashtable {
            param($Object)
            $hash = @{}
            if ($null -eq $Object) { return $hash }
            foreach ($prop in $Object.PSObject.Properties) {
                $hash[$prop.Name] = $prop.Value
            }
            return $hash
        }
    }

    It "should correctly convert a PSCustomObject to a Hashtable" {
        $json = '{"dir_path": ".", "search_string": "*"}'
        $obj = $json | ConvertFrom-Json
        
        $obj.GetType().Name | Should Be "PSCustomObject"
        
        $hash = ConvertTo-Hashtable -Object $obj
        
        $hash.GetType().Name | Should Be "Hashtable"
        $hash.dir_path | Should Be "."
        $hash.search_string | Should Be "*"
        $hash.Count | Should Be 2
    }

    It "should successfully splat a converted Hashtable into a function" {
        $json = '{"param1": "val1"}'
        $obj = $json | ConvertFrom-Json
        $params = ConvertTo-Hashtable -Object $obj
        
        function Test-Splat {
            param($param1)
            return $param1
        }

        $result = & {
            param($p)
            function Inner-Func {
                param($param1)
                return $param1
            }
            Inner-Func @p
        } -p $params

        $result | Should Be "val1"
    }
}
