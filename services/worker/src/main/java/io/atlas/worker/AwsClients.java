package io.atlas.worker;

import java.net.URI;
import java.time.Duration;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.http.urlconnection.UrlConnectionHttpClient;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.s3.S3Client;

@Configuration
public class AwsClients {
    @Bean SqsClient sqs(@Value("${atlas.aws-region}") String region, @Value("${atlas.aws-endpoint}") String endpoint) {
        var builder = SqsClient.builder().region(Region.of(region)).httpClientBuilder(UrlConnectionHttpClient.builder().socketTimeout(Duration.ofSeconds(30)));
        if (!endpoint.isBlank()) builder.endpointOverride(URI.create(endpoint));
        return builder.build();
    }
    @Bean S3Client s3(@Value("${atlas.aws-region}") String region, @Value("${atlas.aws-endpoint}") String endpoint) {
        var builder = S3Client.builder().region(Region.of(region)).forcePathStyle(!endpoint.isBlank());
        if (!endpoint.isBlank()) builder.endpointOverride(URI.create(endpoint));
        return builder.build();
    }
}
