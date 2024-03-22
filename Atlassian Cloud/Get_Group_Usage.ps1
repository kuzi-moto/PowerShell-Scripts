                $Roles.$_ = @{
                    id = ($ProjectRoles.$_ | Select-String -Pattern '(\d+)$').Matches.Groups[0].Value
                }
            $Roles
