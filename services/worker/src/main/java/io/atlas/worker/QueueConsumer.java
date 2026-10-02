package io.atlas.worker;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.ReceiveMessageRequest;
import software.amazon.awssdk.services.sqs.model.DeleteMessageRequest;

@Component
public class QueueConsumer {
    private static final Logger log = LoggerFactory.getLogger(QueueConsumer.class);
    private final SqsClient sqs;
    private final OperationProcessor processor;
    private final String queue;
    public QueueConsumer(SqsClient sqs, OperationProcessor processor, @Value("${atlas.queue-url}") String queue) {
        this.sqs = sqs; this.processor = processor; this.queue = queue;
    }
    @Scheduled(fixedDelay = 1000)
    public void poll() {
        try {
            var response = sqs.receiveMessage(ReceiveMessageRequest.builder().queueUrl(queue).maxNumberOfMessages(5).waitTimeSeconds(10).visibilityTimeout(60).build());
            for (var message : response.messages()) {
                try {
                    processor.process(message.body());
                    sqs.deleteMessage(DeleteMessageRequest.builder().queueUrl(queue).receiptHandle(message.receiptHandle()).build());
                    log.info("Processed message {}", message.messageId());
                } catch (Exception e) { log.error("Message {} failed; queue retry policy applies", message.messageId(), e); }
            }
        } catch (Exception e) { log.warn("Queue unavailable; retrying: {}", e.getClass().getSimpleName()); }
    }
}
