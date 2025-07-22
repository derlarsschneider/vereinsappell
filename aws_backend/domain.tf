data "aws_route53_zone" "derlarsschneider_de" {
    name         = "derlarsschneider.de."
    private_zone = false
}

resource "aws_acm_certificate" "api_cert" {
    domain_name               = "vereinsappell.derlarsschneider.de"
    validation_method         = "DNS"

    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_apigatewayv2_domain_name" "custom_domain" {
    domain_name = "vereinsappell.derlarsschneider.de"

    domain_name_configuration {
        certificate_arn = aws_acm_certificate.api_cert.arn
        endpoint_type   = "REGIONAL"
        security_policy = "TLS_1_2"
    }
}

resource "aws_route53_record" "cert_validation" {
    for_each = {
        for dvo in aws_acm_certificate.api_cert.domain_validation_options : dvo.domain_name => {
            name   = dvo.resource_record_name
            type   = dvo.resource_record_type
            record = dvo.resource_record_value
        }
    }

    zone_id = data.aws_route53_zone.derlarsschneider_de.zone_id
    name    = each.value.name
    type    = each.value.type
    ttl     = 60
    records = [each.value.record]
}

resource "aws_acm_certificate_validation" "cert_validation_complete" {
    certificate_arn         = aws_acm_certificate.api_cert.arn
    validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

resource "aws_apigatewayv2_api_mapping" "api_mapping" {
    api_id      = aws_apigatewayv2_api.http_api.id
    domain_name = aws_apigatewayv2_domain_name.custom_domain.id
    stage       = aws_apigatewayv2_stage.default.name
}

resource "aws_route53_record" "api_alias" {
    zone_id = data.aws_route53_zone.derlarsschneider_de.zone_id # deine Hosted Zone ID für derlarsschneider.de
    name    = "vereinsappell"     # nur der Subdomain-Teil
    type    = "A"

    alias {
        name                   = aws_apigatewayv2_domain_name.custom_domain.domain_name_configuration[0].target_domain_name
        zone_id                = aws_apigatewayv2_domain_name.custom_domain.domain_name_configuration[0].hosted_zone_id
        evaluate_target_health = false
    }
}
